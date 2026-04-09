# Moth v2 — Production Tambola Server

> **Date:** 2026-04-10
> **Status:** Approved (revised after adversarial review)
> **Scope:** Full rewrite of the Moth POC into a production-grade, single-node (cluster-ready) Tambola/Housie game server.

---

## 1. Goals & Constraints

### What We're Building

A production-grade Tambola (Housie/Bingo) game server that can reliably host thousands of concurrent games with tens of thousands of connected players on a single node. The server supports both a mobile-friendly web interface (Phoenix LiveView) and native mobile apps (REST API + Phoenix Channels).

### Target Scale

- ~10K concurrent games, ~100K connected players on a single 64GB node
- Cluster support requires additional design work (state handoff, conflict resolution, net-split handling) beyond what this spec covers. The architecture is designed to make clustering feasible, not trivial.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Architecture | Context-separated monolith (single OTP app) | Clean boundaries without umbrella overhead. Matches how successful Phoenix apps at scale are structured. |
| Web interface | Phoenix LiveView, mobile-first | Simplifies stack — no separate frontend. Real-time built in. |
| Native mobile support | REST API + Phoenix Channels | Same game engine underneath LiveView and the API. Channels for real-time, HTTP for actions. |
| Auth | Magic links (primary) + Google OAuth. Apple OAuth deferred. | No passwords. Mobile-friendly. Apple deferred until a maintained `ueberauth_apple` library exists or we implement the OAuth flow manually. |
| Game rooms | Private, invite-based (join codes) | No public lobby to maintain at scale. |
| Game mechanics | Faithful Tambola with player-initiated claims | Server generates tickets, validates claims. Players must actively claim prizes. Bogey system for invalid claims. |
| Rewrite vs patch | Full rewrite | POC has 42 cataloged issues. Moving to LiveView, new auth, new supervision — patching would be more work than starting fresh. |

### Non-Goals (v1)

- Apple OAuth (deferred — no stable library)
- Multi-node clustering (architecture is cluster-aware but v1 is single-node)
- Chat moderation / persistence
- Game replay / spectator mode

---

## 2. System Architecture

### Supervision Tree

```
Moth.Application (top-level supervisor, strategy: rest_for_one)
├── Moth.Repo (Ecto)
├── Phoenix.PubSub (name: Moth.PubSub)
├── MothWeb.Telemetry
├── Moth.Game.Supervisor (top-level game subtree, strategy: rest_for_one)
│   ├── {Registry, keys: :unique, name: Moth.Game.Registry}
│   ├── {DynamicSupervisor, name: Moth.Game.DynSup, strategy: :one_for_one}
│   └── Moth.Game.Monitor (GenServer — reconstructs tracking state from Registry on init)
├── MothWeb.Presence
└── MothWeb.Endpoint
```

**Why `rest_for_one` for the game subtree:** Monitor depends on Registry and DynamicSupervisor. If either crashes and restarts, Monitor must also restart to rebuild its tracking state from the new Registry. `rest_for_one` guarantees this ordering — children after the crashed child are restarted in order.

**Monitor responsibilities:**
- Tracks active game count and publishes telemetry metrics
- Reaps abandoned lobby-state games after 1 hour of inactivity
- Reaps finished games after the cooldown period (configurable, default 30 minutes)
- Reconstructs its tracking state from `Registry.select/2` on init (crash-safe)

### Context Boundaries

| Context | Owns | Public API |
|---------|------|------------|
| `Moth.Auth` | Users, identities, tokens, magic links, OAuth | `register/1`, `authenticate_magic_link/1`, `authenticate_oauth/2`, `get_user!/1`, `get_user_by_api_token/1`, `generate_user_session_token/1`, `generate_api_token/1`, `revoke_all_tokens/1` |
| `Moth.Game` | GameServer, Board, Tickets, Prizes, Room codes, game persistence | `create_game/2`, `join_game/2`, `game_state/1`, `start_game/2`, `pause/2`, `resume/2`, `end_game/2`, `claim_prize/3`, `send_chat/3` |
| `MothWeb` | LiveView, API controllers, Channels, Auth flows, Plugs | Consumes `Moth.Auth` + `Moth.Game` — never touches GenServers or DB directly |

**The key rule:** `MothWeb` never calls a GenServer directly or queries the DB. Everything goes through context APIs. The game engine publishes events to PubSub; LiveView and Channels subscribe.

---

## 3. Game Engine (`Moth.Game`)

### GameServer — One GenServer Per Game

Each game is a single GenServer under a DynamicSupervisor. Board state is embedded in the GenServer state (no separate Agent process — fixes the POC's Agent leak and atomicity issues).

**GenServer state:**

```elixir
%Moth.Game.Server{
  id: "abc123",
  code: "TIGER-42",        # human-friendly join code
  host_id: 1,              # user who created the game
  status: :lobby,          # :lobby → :running → :paused → :finished
  board: %Board{},         # bag, picks, count — embedded struct
  tickets: %{},            # user_id → generated ticket
  players: MapSet.new(),   # set of user_ids currently in the game
  prizes: [...],           # prize definitions + winners
  bogeys: %{},             # user_id → bogey count
  settings: %{},           # interval, bogey_limit, enabled_prizes
  timer_ref: nil,          # Process.send_after ref
  next_pick_at: nil,       # DateTime — sent to clients for local countdown
  host_disconnect_ref: nil, # auto-pause timer when host disconnects
  started_at: nil,
  finished_at: nil
}
```

### Game Lifecycle

1. **`:lobby`** — Game created, players join via code, host can configure. No numbers picked. Auto-reaped after 1 hour of inactivity by Monitor.
2. **`:running`** — Host starts the game. Timer ticks, numbers auto-picked and broadcast via PubSub.
3. **`:paused`** — Host pauses (or auto-paused on host disconnect). Timer cancelled atomically inside the GenServer. Resume restarts the timer.
4. **`:finished`** — All 90 numbers picked or host ends early. Final state persisted to DB. Process stays alive for a configurable cooldown (default 30 minutes) so players can review results, then terminates cleanly.

### Settings Constraints

| Setting | Min | Max | Default |
|---------|-----|-----|---------|
| `interval` (seconds between picks) | 10 | 120 | 30 |
| `bogey_limit` (strikes before disqualification) | 1 | 10 | 3 |
| `enabled_prizes` | at least 1 | all 5 | all 5 |

The minimum interval of 10 seconds bounds the maximum snapshot write rate: at 10K games with 10s intervals, snapshots every 5 picks = ~200 snapshots/sec (well within Postgres capability).

### Race Condition Fixes

- Pause/resume happen inside `handle_call` — no TOCTOU races. Timer ref is tracked; old timers cancelled before new ones start.
- Board operations are pure functions called within the GenServer — no concurrent access possible.
- `Board.pick/1` on an empty bag returns `{:finished, state}` instead of crashing.
- Prize claims are serialized through the GenServer mailbox — exactly one winner per prize, no races.

### Crash Recovery

**Two-tier persistence strategy:**

1. **Write-through for critical mutations:** Prize claims and player joins write to the DB synchronously (inside `handle_call`) before broadcasting via PubSub. These are low-frequency, high-value events that must not be lost.

2. **Periodic snapshots for board state:** The board (bag, picks, count) is snapshotted to `games.snapshot` every 5 picks. This is the only data that can be lost on crash — up to 4 picks. Players reconnecting after a crash-recovery will see the board reset to the last snapshot, but all prize claims and player records are intact.

**Recovery flow:**

```
GameServer crashes
  → DynamicSupervisor restarts it (new PID)
  → init/1 loads games.snapshot from DB
  → Re-registers in Registry (old entry auto-cleaned on process death)
  → Loads player tickets and prize state from game_players table
  → Resumes timer from snapshot board state
  → Broadcasts "game:CODE:status" with {:recovered, last_pick_count}
```

**Restart gap handling:** Between crash and re-registration, `Registry.lookup` returns `[]`. The `Moth.Game` context API returns `{:error, :game_unavailable}` in this case. LiveView and Channel clients show a "Reconnecting..." state and retry with exponential backoff (max 5 seconds).

### PubSub Events

| Event | Payload | When |
|-------|---------|------|
| `game:CODE:pick` | `%{number: 42, count: 15, next_pick_at: ~U[...]}` | Number picked. Includes timestamp for client-side countdown. |
| `game:CODE:status` | `%{status: :paused, by: user}` | Pause/resume/finish/recovered |
| `game:CODE:player_joined` | `%{user: ...}` | Player joins |
| `game:CODE:player_left` | `%{user_id: ...}` | Player leaves |
| `game:CODE:prize_claimed` | `%{prize: ..., winner: ...}` | Valid prize claim |
| `game:CODE:bogey` | `%{user: ..., prize: ..., remaining: N}` | Invalid claim |
| `game:CODE:chat` | `%{user: ..., text: ...}` | Chat message |

**No timer broadcast.** Clients compute their own countdown from `next_pick_at` in the last `pick` event. This eliminates 10K broadcasts/sec at scale that carry zero gameplay value. The server only broadcasts when something actually happens (a pick, a claim, a status change).

---

## 4. Tickets & Prize Claims

### Ticket Generation (Server-Side)

Each player gets a ticket generated by the server. Standard Tambola rules:

- 3 rows x 9 columns
- Each row has exactly 5 numbers and 4 blanks
- Column 1: numbers 1-9, Column 2: 10-19, ..., Column 9: 80-90
- Numbers within a column are sorted top to bottom
- 15 unique numbers total per ticket

Tickets stored in GenServer state (`tickets` map keyed by `user_id`). The server is the source of truth.

**When tickets are assigned:**
- Players in the lobby when the host starts the game: tickets generated at game start.
- Players who join after the game has started: ticket generated on join. They can claim prizes based on numbers already picked (no disadvantage — their ticket is fresh and may already have matches).
- Players cannot join a finished game.

**Ticket persistence:** On assignment, the ticket is written to `game_players.ticket` (write-through). This ensures tickets survive crashes and enables reconnection — a reconnecting player gets their original ticket back from the GenServer state (or from DB if recovering from crash).

### Prize Claiming (Player-Initiated, Server-Validated)

1. Player watches numbers being picked and tracks their ticket.
2. Player believes they've completed a prize and hits "Claim."
3. Server validates the claim against the player's ticket and picked numbers.
4. If valid and unclaimed: prize awarded, written to DB (write-through), then broadcast to all.
5. If invalid: bogey issued, player notified.

**Concurrent claims:** All claims are serialized through the GenServer's `handle_call`. If two players claim the same prize "simultaneously," one arrives first and wins; the second gets `{:error, :already_claimed}` (not a bogey — the prize was valid at the time they pressed the button).

### Bogey System

Invalid claims (numbers not yet picked, wrong row, etc.) result in a bogey (strike). After N bogeys (configurable by host, default 3), the player is disqualified from claiming further prizes. Discourages spam-claiming.

A claim for an already-claimed prize is **not** a bogey — it's a race the player lost.

### Standard Prizes

| Prize | Rule |
|-------|------|
| Early Five | First player whose any 5 ticket numbers have been picked |
| Top Line | First player whose entire row 1 is picked |
| Middle Line | First player whose entire row 2 is picked |
| Bottom Line | First player whose entire row 3 is picked |
| Full House | First player whose all 15 numbers are picked |

Host configures which prizes are active at game creation time.

---

## 5. Authentication (`Moth.Auth`)

### Auth Methods

| Method | Flow | Status |
|--------|------|--------|
| **Magic Link** (primary) | Enter email → server sends signed, time-limited link → click → session created | v1 |
| **Google OAuth** | Ueberauth flow → find or create user by email → session | v1 |
| **Apple OAuth** | Manual OAuth implementation or future library | Deferred |

All methods resolve to the same user via email address. A user can have multiple linked OAuth identities.

### Magic Link Tokens

- Token generated, hashed (SHA-256), stored in `user_tokens` with context `"magic_link"`.
- Plain token sent via email link.
- On click: hash incoming token, match against DB, check expiry, mark used, create session.
- Single-use, time-limited (15 minutes).
- If the email doesn't arrive: the `MagicLinkLive` page shows a "Resend" button (rate-limited to 1 per 60 seconds per email). Clear messaging: "Check your spam folder."

### Token Lifecycle

| Token type | Context | Expiry | Rotation | Revocation |
|------------|---------|--------|----------|------------|
| Session (web) | `"session"` | 60 days | New token on each login | Logout deletes token. `revoke_all_tokens/1` clears all. |
| API (mobile) | `"api"` | 30 days | Client requests new token before expiry via `POST /api/auth/refresh` | Logout deletes token. `revoke_all_tokens/1` clears all. |
| Magic link | `"magic_link"` | 15 minutes | N/A — single use | Marked `used_at` on consumption. Expired tokens cleaned by periodic job. |

`revoke_all_tokens/1` is the "compromised account" emergency button — invalidates all sessions and API tokens for a user.

### Dual Session Strategy

- **Web (LiveView):** Standard Phoenix session cookie via `phx.gen.auth` pattern — `user_token` in session, `user_tokens` table.
- **Native mobile:** Bearer token in `Authorization` header for API, token in Channel connect params. Same `user_tokens` table, different context.

### Email Delivery

Swoosh with configurable adapter. Dev: `Swoosh.Adapters.Local` + mailbox viewer at `/dev/mailbox`. Prod: any SMTP/API provider.

---

## 6. Connection Resilience

### Host Disconnect

When the host's LiveView or Channel process terminates (browser closed, phone dies, network drop):

1. `MothWeb.Presence` detects the host left.
2. GameServer receives `player_left` for the host's user_id.
3. GameServer starts a 60-second auto-pause timer (`host_disconnect_ref`).
4. If the host reconnects within 60 seconds: timer cancelled, game continues.
5. If the timer fires: game auto-pauses, broadcasts `%{status: :paused, by: :system, reason: :host_disconnected}`.
6. Game remains paused until the host reconnects and explicitly resumes.
7. If the host doesn't reconnect within the game's cooldown period: game is finished and reaped.

### Player Disconnect & Reconnect

- A player disconnecting does not affect the game — it continues.
- On reconnect (same user_id joins the same game code): the player gets their **original ticket** back from GenServer state (or DB if post-crash). No new ticket is generated.
- All numbers picked during their absence are available in the game state payload sent on join.
- Their bogey count is preserved.

### Multi-Device / Duplicate Sessions

A player can connect from multiple devices (two browser tabs, phone + laptop). The `game_players` table has a unique constraint on `(game_id, user_id)`, and the GenServer tracks one ticket per `user_id`. Multiple connections for the same user:
- Both receive all PubSub events (each LiveView/Channel process subscribes independently).
- Both show the same ticket.
- Claims are deduplicated by `user_id` in the GenServer — the first claim wins, the second gets `{:error, :already_claimed}` for that prize.
- Bogeys are tracked per `user_id`, not per connection.

---

## 7. Web Interface (`MothWeb` — LiveView)

### Routes

| Route | LiveView | Purpose |
|-------|----------|---------|
| `/` | `HomeLive` | Landing, login entry point |
| `/auth/magic` | `MagicLinkLive` | Email input → "check your inbox" → resend |
| `/auth/callback/:provider` | Controller | OAuth callback, redirects |
| `/game/new` | `Game.NewLive` | Create game — name, prizes, bogey limit, interval |
| `/game/:code` | `Game.PlayLive` | Main game room — ticket, board, chat, claims |
| `/game/:code/host` | `Game.HostLive` | Host controls — start, pause, resume, end |
| `/profile` | `ProfileLive` | Link OAuth accounts, update name |

### `Game.PlayLive` — Core Screen (Mobile-First)

```
┌─────────────────────────┐
│  Game: "Friday Housie"  │  ← game name, status
│  Next pick in: 12s      │  ← client-side countdown from next_pick_at
├─────────────────────────┤
│  ┌─┬─┬─┬─┬─┬─┬─┬─┬─┐  │
│  │4│ │ │23│ │50│ │71│ │  │  ← player's ticket
│  ├─┼─┼─┼─┼─┼─┼─┼─┼─┤  │     picked numbers highlighted
│  │ │12│ │ │40│ │62│ │85│  │     tap to daub (visual only)
│  ├─┼─┼─┼─┼─┼─┼─┼─┼─┤  │
│  │ │ │30│ │ │55│ │78│90│  │
│  └─┴─┴─┴─┴─┴─┴─┴─┴─┘  │
├─────────────────────────┤
│ [Claim: Top] [Mid] [Bot]│  ← claim buttons for unclaimed prizes
│ [Early 5]  [Full House] │
├─────────────────────────┤
│  Picked: 42 17 83 5 ... │  ← scrollable picked numbers
├─────────────────────────┤
│  Top Line: Priya         │  ← prize feed
│  Bogey: Raj (2 left)    │
├─────────────────────────┤
│  Chat...                 │  ← in-game chat
└─────────────────────────┘
```

### Real-Time Updates

LiveView processes subscribe to `game:CODE:*` PubSub topics on mount. Each game event triggers `handle_info` → update assigns → re-render. Each UI section is a separate LiveComponent for minimal re-rendering.

**Countdown timer:** Implemented client-side via a JS hook. On each `pick` event, LiveView pushes `next_pick_at` to the hook, which runs `setInterval` locally. No server-side timer broadcasts.

**Reconnecting state:** If `Moth.Game.game_state/1` returns `{:error, :game_unavailable}`, the LiveView shows "Reconnecting..." and retries with backoff.

### Mobile-Friendly

Large tap targets, no hover states, viewport meta tag, Tailwind CSS (ships with Phoenix).

---

## 8. Native Mobile API

### REST Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/api/auth/magic` | Request magic link email |
| `POST` | `/api/auth/verify` | Verify magic link token → bearer token |
| `POST` | `/api/auth/oauth/:provider` | Exchange OAuth code → bearer token |
| `POST` | `/api/auth/refresh` | Refresh expiring API token |
| `DELETE` | `/api/auth/session` | Logout, revoke token |
| `GET` | `/api/user/me` | Current user profile |
| `PATCH` | `/api/user/me` | Update name/avatar |
| `POST` | `/api/games` | Create game |
| `GET` | `/api/games/:code` | Game details |
| `POST` | `/api/games/:code/join` | Join game, receive ticket |
| `POST` | `/api/games/:code/start` | Host starts game |
| `POST` | `/api/games/:code/pause` | Host pauses |
| `POST` | `/api/games/:code/resume` | Host resumes |
| `POST` | `/api/games/:code/end` | Host ends early |
| `POST` | `/api/games/:code/claim` | Player claims prize `{prize: "top_line"}` |

**Auth:** Bearer token in `Authorization` header. Tokens expire after 30 days.

**CORS:** Configured on the API pipeline to allow requests from mobile app origins. Wildcard `*` in dev, explicit origins in prod.

**Error format:** Consistent shape, proper HTTP status codes (401, 403, 404, 422, 429).

```json
{"error": {"code": "invalid_claim", "message": "Numbers not yet picked"}}
```

### Channel (Real-Time for Mobile)

Socket at `/api/socket`, authenticated via bearer token in connect params.

Topic: `"game:CODE"`

Server → Client events mirror the PubSub events (pick, status, player_joined, player_left, prize_claimed, bogey, chat). No timer events — clients compute countdown from `next_pick_at` in pick payloads.

Client → Server: Channel is read-only for game events. All actions go through REST. Exception: chat messages go through Channel (`push "message", %{text: "..."}`) since they're high-frequency.

### Rate Limiting

| Scope | Limit |
|-------|-------|
| Auth endpoints | 5 req/min per IP |
| Game creation | 10 req/hour per user |
| Prize claims | 1 req/sec per user per game |
| General API | 60 req/min per user |
| Game join (failed attempts) | 10 req/min per IP (prevents code enumeration) |
| Chat (Channel) | 1 msg/sec per user (enforced in GameServer) |

ETS-based token bucket, applied at router pipeline level for REST and in the GameServer for chat.

---

## 9. Data Model

### Tables

**users**

| Column | Type | Constraints |
|--------|------|-------------|
| id | bigint | PK |
| email | string | unique, not null |
| name | string | not null |
| avatar_url | string | |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

**user_identities**

| Column | Type | Constraints |
|--------|------|-------------|
| id | bigint | PK |
| user_id | bigint | FK → users, not null |
| provider | string | not null ("google") |
| provider_uid | string | not null |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

Indexes: unique on `(provider, provider_uid)`, unique on `(user_id, provider)`.

**user_tokens**

| Column | Type | Constraints |
|--------|------|-------------|
| id | bigint | PK |
| user_id | bigint | FK → users, not null |
| token | binary | not null (hashed) |
| context | string | not null ("session", "api", "magic_link") |
| sent_to | string | email for magic links |
| expires_at | utc_datetime | not null |
| used_at | utc_datetime | single-use magic links |
| inserted_at | utc_datetime | |

Index: on `token` for lookup. Index: on `(user_id, context)` for revocation.

**games**

| Column | Type | Constraints |
|--------|------|-------------|
| id | bigint | PK |
| code | string | unique, not null |
| name | string | not null |
| host_id | bigint | FK → users, not null |
| status | string | not null, default "lobby" |
| settings | jsonb | interval, bogey_limit, enabled_prizes |
| started_at | utc_datetime | |
| finished_at | utc_datetime | |
| snapshot | jsonb | last persisted board state for crash recovery |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

Indexes: on `status`, on `host_id`, unique on `code`.

**Status enum mapping:** GenServer uses atoms (`:lobby`, `:running`, `:paused`, `:finished`). DB stores strings (`"lobby"`, `"running"`, `"paused"`, `"finished"`). An Ecto custom type `Moth.Game.StatusEnum` handles the conversion at the persistence boundary.

**game_players**

| Column | Type | Constraints |
|--------|------|-------------|
| id | bigint | PK |
| game_id | bigint | FK → games, not null |
| user_id | bigint | FK → users, not null |
| ticket | jsonb | generated ticket |
| prizes_won | string[] | e.g. ["top_line", "full_house"] |
| bogeys | integer | default 0 |
| inserted_at | utc_datetime | |

Indexes: unique on `(game_id, user_id)`.

### What Stays In-Memory Only

- Current board state (bag, picks) — reconstructable from snapshot
- Timer state (`timer_ref`, `next_pick_at`)
- Real-time player connections (who's currently online vs. who has joined)

### Persistence Strategy

| Event | Persistence | Rationale |
|-------|-------------|-----------|
| Game creation | Write-through | Must survive any failure |
| Player join + ticket assignment | Write-through (`game_players` row) | Ticket must survive crashes |
| Prize claim | Write-through (`game_players.prizes_won`) | Prizes must never be lost |
| Board state (picks) | Periodic snapshot (every 5 picks) | Acceptable to lose up to 4 picks on crash |
| Chat messages | Not persisted | Ephemeral by design |
| Game finish | Write-through (final state) | Permanent record |

---

## 10. Chat

Chat is ephemeral — messages are broadcast via PubSub and not persisted to the database. No chat history is available after disconnecting.

**Rate limiting:** 1 message per second per user, enforced inside the GameServer. Excess messages are silently dropped.

**Moderation:** No automated moderation in v1. The host can end the game if chat becomes problematic. Chat moderation (word filters, mute, etc.) is a future enhancement.

**Transport:** Chat messages go through the GameServer (via `Moth.Game.send_chat/3`) which broadcasts on the `game:CODE:chat` PubSub topic. For web, LiveView handles the event. For mobile, the Channel relays it. This ensures rate limiting is applied uniformly regardless of transport.

---

## 11. Scalability & Operations

### Memory Budget (Single 64GB Node)

| Component | Per-unit | At target scale |
|-----------|----------|-----------------|
| GameServer process | ~50KB | 10K x 50KB = ~500 MB |
| LiveView process | ~30KB | 100K x 30KB = ~3 GB |
| Channel process | ~20KB | share of 100K connections |
| ETS caches | — | < 100 MB |
| BEAM overhead | — | ~2-4 GB |

Comfortable headroom on a 64GB node for ~10K games / ~100K players.

### Cluster-Readiness

The architecture is designed to make future clustering feasible, not to make it a configuration change:

| Concern | Single-node (v1) | What clustering requires |
|---------|-------------------|--------------------------|
| Game Registry | Local `Registry` | Distributed registry (Horde or custom). Requires conflict resolution for net-split scenarios where two nodes start the same game. |
| Game Supervisor | Local `DynamicSupervisor` | Distributed supervisor. Requires state handoff when a node joins/leaves. |
| PubSub | `Phoenix.PubSub` (PG2) | Already distributed across nodes — works out of the box. |
| DB | Single Postgres | Same — Ecto pools per node. |
| Load balancing | N/A | Sticky sessions by game code (WebSocket affinity). |

`Moth.Game` context wraps Registry and DynamicSupervisor calls through its own functions, so the game logic doesn't depend on the backing implementation. But clustering is a design project, not a flag flip.

### Graceful Shutdown

On SIGTERM:
1. Stop accepting new connections (Endpoint draining).
2. Broadcast "server shutting down" to all game topics.
3. Persist all game snapshots to DB. Timeout: 30 seconds. Games that fail to snapshot are logged but don't block shutdown.
4. Drain existing connections with a 15-second grace period.
5. Terminate.

### Observability

- `Phoenix.LiveDashboard` for process counts, memory, message queues
- Telemetry events: game created/finished, pick, prize claim, player join/leave, auth, snapshot writes
- Structured logging with game_id + user_id for traceability
- Health check endpoint at `/health` for load balancers (returns 200 if Repo and PubSub are alive)

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Game with 0 players when started | Host can start with 0 players (solo testing). Game runs normally. |
| Game with 0 connected players (all disconnected) | Game continues running. If host disconnected, auto-pause after 60s. Monitor reaps after cooldown. |
| Host starts game then immediately disconnects | Game runs for 60s, then auto-pauses. Players see "Host disconnected, game paused." |
| Player joins, gets ticket, immediately disconnects | Ticket is persisted. Player can reconnect anytime before game finishes. |

---

## 12. Project Structure

```
lib/
├── moth/
│   ├── application.ex
│   ├── repo.ex
│   ├── mailer.ex
│   ├── auth/
│   │   ├── auth.ex              # context API
│   │   ├── user.ex              # schema
│   │   ├── user_identity.ex     # schema
│   │   ├── user_token.ex        # schema + token logic
│   │   └── user_notifier.ex     # magic link email
│   └── game/
│       ├── game.ex              # context API (public interface)
│       ├── server.ex            # GenServer
│       ├── board.ex             # pure functions for bag/pick logic
│       ├── ticket.ex            # pure functions for ticket generation
│       ├── prize.ex             # pure functions for claim validation
│       ├── code.ex              # room code generation (WORD-NN)
│       ├── record.ex            # Ecto schema for games table
│       ├── player.ex            # Ecto schema for game_players table
│       ├── status_enum.ex       # Ecto custom type for status atom ↔ string
│       ├── monitor.ex           # GenServer for tracking/reaping
│       └── supervisor.ex        # Supervisor (rest_for_one) wrapping Registry + DynSup + Monitor
├── moth_web/
│   ├── endpoint.ex
│   ├── router.ex
│   ├── telemetry.ex
│   ├── presence.ex
│   ├── components/
│   │   ├── layouts.ex
│   │   ├── core_components.ex
│   │   └── game_components.ex   # ticket, board, prize feed, claims
│   ├── live/
│   │   ├── home_live.ex
│   │   ├── magic_link_live.ex
│   │   ├── profile_live.ex
│   │   └── game/
│   │       ├── new_live.ex
│   │       ├── play_live.ex
│   │       └── host_live.ex
│   ├── controllers/
│   │   ├── auth_controller.ex       # OAuth callbacks
│   │   └── api/
│   │       ├── auth_controller.ex   # magic link + OAuth for mobile
│   │       ├── game_controller.ex   # game CRUD + actions
│   │       └── user_controller.ex   # profile
│   ├── channels/
│   │   ├── game_socket.ex           # authenticated socket for mobile
│   │   └── game_channel.ex          # PubSub relay to mobile
│   └── plugs/
│       ├── auth.ex                  # session auth for web
│       ├── api_auth.ex              # bearer token auth for mobile
│       └── rate_limit.ex
```

---

## 13. Testing Strategy

### Test Matrix

| Layer | What | How |
|-------|------|-----|
| **Pure functions** | Board, Ticket, Prize, Code | ExUnit. Property-based tests (StreamData) for ticket validity and board exhaustion. |
| **GenServer** | Server lifecycle, state transitions, crash recovery | ExUnit with `start_supervised`. Full lifecycle: lobby → running → pause → resume → finish. Crash + restart from snapshot. |
| **Context integration** | `Moth.Auth`, `Moth.Game` public APIs | ExUnit with Ecto sandbox. Auth flows, game creation, player join, prize claims. |
| **LiveView / API** | Web and mobile interfaces | `Phoenix.LiveViewTest` for web, `Phoenix.ConnTest` for API. |
| **Concurrency** | Prize claim races | Spawn N tasks calling `claim_prize/3` concurrently against one GameServer. Assert exactly one winner. |

### Property-Based Tests (StreamData)

- `Ticket.generate/2` always produces valid Tambola tickets (5 per row, correct column ranges, 15 total, sorted within columns)
- `Board.pick/1` never repeats, always exhausts exactly 1-90
- `Prize.check_claim/3` never validates an incomplete claim
- `Code.generate/0` produces codes matching the `WORD-NN` format

### Specific Scenarios That Must Pass

**Game Engine:**
- Full game lifecycle: create → join 3 players → start → pick all 90 → all prizes claimed → finish
- Crash mid-game (kill GenServer) → restart from snapshot → prizes and tickets intact → game continues
- Pause while timer message is in-flight → no extra pick happens
- Double-resume → only one timer chain running
- Player claims prize → second player claims same prize → first wins, second gets `{:error, :already_claimed}`
- Player accumulates N bogeys → disqualified → further claims rejected
- Host disconnects → auto-pause after 60s → host reconnects → resumes

**Auth:**
- Magic link: request → verify → session created → token single-use (second verify fails)
- OAuth: Google login → user created → second login → same user
- API token: authenticate → use → expires → 401
- `revoke_all_tokens/1` → all sessions and API tokens invalidated

**Connection Resilience:**
- Player disconnects and reconnects → same ticket, same bogey count
- Same user from two devices → same ticket, claims deduplicated

### No Mocks

Real context APIs, real GenServers (`start_supervised`), real DB (Ecto sandbox).

### Load Testing

Not part of the automated test suite. Manual load testing with a custom Mix task (`mix moth.load_test`) that:
- Spawns N game servers
- Simulates M players per game via WebSocket connections
- Measures: pick broadcast latency (p99 < 100ms), claim response time (p99 < 200ms), memory per game, snapshot write throughput
- Target: 1K games / 10K players on a dev machine as a smoke test. Full-scale testing on production-grade hardware before launch.

---

## 14. Dependencies

### New Dependencies

| Dep | Purpose |
|-----|---------|
| `phoenix ~> 1.7` | Web framework |
| `phoenix_live_view ~> 0.20` | Real-time web UI |
| `phoenix_live_dashboard ~> 0.8` | Observability |
| `phoenix_html ~> 3.3` | HTML helpers (required by LiveView) |
| `ecto_sql ~> 3.10` + `postgrex` | Database |
| `swoosh` | Email delivery (magic links) |
| `ueberauth ~> 0.10` | OAuth framework |
| `ueberauth_google ~> 0.12` | Google OAuth |
| `jason ~> 1.2` | JSON |
| `bandit ~> 1.0` | HTTP server (replaces plug_cowboy) |
| `dns_cluster ~> 0.1` | Cluster discovery |
| `telemetry_metrics + telemetry_poller` | Observability |
| `esbuild ~> 0.8` | Asset build |
| `tailwind ~> 0.2` | CSS |
| `stream_data` (test only) | Property-based testing |
| `cors_plug ~> 3.0` | CORS for mobile API |

### Dropped from POC

`sqids`, `req`, `hashids`, `plug_cowboy` (replaced by Bandit).

### Deferred

`ueberauth_apple` — no stable Hex package exists. Apple OAuth will be added in a future version, either via a maintained library or a manual OAuth implementation.

---

## 15. Room Code Design

Codes follow the format `WORD-NN` (e.g., `TIGER-42`, `OCEAN-17`).

**Word list:** ~2,000 common, easy-to-spell English words (no offensive words, no homophones that cause confusion). Total code space: 2,000 x 100 = 200,000 unique codes. At 10K concurrent games, collision probability is low.

**Generation:** `Moth.Game.Code.generate/0` picks a random word + random 2-digit number, checks uniqueness against the Registry (in-memory, fast), retries on collision (max 10 attempts). If all attempts fail (extremely unlikely), falls back to a random 8-character alphanumeric code.

**Failed join rate limiting:** 10 failed join attempts per minute per IP (Section 8 rate limits). This prevents brute-force code enumeration. With 200K code space and 10K active codes, an attacker has a ~5% hit rate per guess — rate limiting makes systematic enumeration impractical.

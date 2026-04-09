# Moth v2 — Production Tambola Server

> **Date:** 2026-04-10
> **Status:** Approved
> **Scope:** Full rewrite of the Moth POC into a production-grade, single-node (cluster-ready) Tambola/Housie game server.

---

## 1. Goals & Constraints

### What We're Building

A production-grade Tambola (Housie/Bingo) game server that can reliably host thousands of concurrent games with tens of thousands of connected players on a single node. The server supports both a mobile-friendly web interface (Phoenix LiveView) and native mobile apps (REST API + Phoenix Channels).

### Target Scale

- ~10K concurrent games, ~100K connected players on a single 64GB node
- Cluster-ready: architecture supports horizontal scaling via Erlang clustering without a rewrite

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Architecture | Context-separated monolith (single OTP app) | Clean boundaries without umbrella overhead. Matches how successful Phoenix apps at scale are structured. |
| Web interface | Phoenix LiveView, mobile-first | Simplifies stack — no separate frontend. Real-time built in. |
| Native mobile support | REST API + Phoenix Channels | Same game engine underneath LiveView and the API. Channels for real-time, HTTP for actions. |
| Auth | Magic links (primary) + Google + Apple OAuth | No passwords. Mobile-friendly. |
| Game rooms | Private, invite-based (join codes) | No public lobby to maintain at scale. |
| Game mechanics | Faithful Tambola with player-initiated claims | Server generates tickets, validates claims. Players must actively claim prizes. Bogey system for invalid claims. |
| Rewrite vs patch | Full rewrite | POC has 42 cataloged issues. Moving to LiveView, new auth, new supervision — patching would be more work than starting fresh. |

---

## 2. System Architecture

### Supervision Tree

```
Moth.Application (top-level supervisor)
├── Moth.Repo (Ecto)
├── Moth.Auth (accounts, tokens, OAuth)
├── Moth.Game.Supervisor (DynamicSupervisor for game servers)
├── Moth.Game.Registry (via Registry, maps game_code → pid)
├── Moth.Game.Monitor (GenServer — tracks counts, cleans up stale games)
├── Phoenix.PubSub (name: Moth.PubSub)
├── MothWeb.Presence
├── MothWeb.Telemetry
└── MothWeb.Endpoint
```

### Context Boundaries

| Context | Owns | Public API |
|---------|------|------------|
| `Moth.Auth` | Users, identities, tokens, magic links, OAuth | `register/1`, `authenticate_magic_link/1`, `authenticate_oauth/2`, `get_user!/1`, `get_user_by_api_token/1`, `generate_user_session_token/1` |
| `Moth.Game` | GameServer, Board, Tickets, Prizes, Room codes, game persistence | `create_game/2`, `join_game/2`, `game_state/1`, `start_game/2`, `pause/2`, `resume/2`, `end_game/2`, `claim_prize/3` |
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
  started_at: nil,
  finished_at: nil
}
```

### Game Lifecycle

1. **`:lobby`** — Game created, players join via code, host can configure. No numbers picked.
2. **`:running`** — Host starts the game. Timer ticks, numbers auto-picked and broadcast via PubSub.
3. **`:paused`** — Host pauses. Timer cancelled atomically inside the GenServer (fixes the POC race condition). Resume restarts the timer.
4. **`:finished`** — All 90 numbers picked or host ends early. State persisted to DB. Process stays alive for a configurable cooldown (players review results), then terminates cleanly.

### Race Condition Fixes

- Pause/resume happen inside `handle_call` — no TOCTOU races. Timer ref is tracked; old timers cancelled before new ones start.
- Board operations are pure functions called within the GenServer — no concurrent access possible.
- `Board.pick/1` on an empty bag returns `{:finished, state}` instead of crashing.

### Crash Recovery

- DynamicSupervisor restarts crashed game servers.
- On init, a restarting server checks the DB for `games.snapshot`.
- If snapshot exists and game not finished: restore state, re-register in Registry, resume timer.
- If no snapshot or game finished: terminate cleanly.
- Snapshot frequency: every 5 picks (configurable). At 30-second intervals, ~67 writes/sec at 10K games — well within Postgres capability.

### PubSub Events

| Event | Payload | When |
|-------|---------|------|
| `game:CODE:pick` | `%{number: 42, count: 15}` | Number picked |
| `game:CODE:timer` | `%{remaining: 12}` | Every second countdown |
| `game:CODE:status` | `%{status: :paused, by: user}` | Pause/resume/finish |
| `game:CODE:player_joined` | `%{user: ...}` | Player joins |
| `game:CODE:player_left` | `%{user_id: ...}` | Player leaves |
| `game:CODE:prize_claimed` | `%{prize: ..., winner: ...}` | Valid prize claim |
| `game:CODE:bogey` | `%{user: ..., prize: ..., remaining: N}` | Invalid claim |

Both LiveView and Channels subscribe to these same topics.

---

## 4. Tickets & Prize Claims

### Ticket Generation (Server-Side)

Each player gets a ticket generated by the server when they join a running game (or when the game starts if they're already in the lobby). Standard Tambola rules:

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

### Prize Claiming (Player-Initiated, Server-Validated)

1. Player watches numbers being picked and tracks their ticket.
2. Player believes they've completed a prize and hits "Claim."
3. Server validates the claim against the player's ticket and picked numbers.
4. If valid and unclaimed: prize awarded, broadcast to all.
5. If invalid: bogey issued, player notified.

### Bogey System

Invalid claims result in a bogey (strike). After N bogeys (configurable by host, default 3), the player is disqualified from claiming further prizes. Discourages spam-claiming.

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

### Three Auth Methods, One User Identity

| Method | Flow |
|--------|------|
| **Magic Link** (primary) | Enter email → server sends signed, time-limited link → click → session created |
| **Google OAuth** | Ueberauth flow → find or create user by email → session |
| **Apple OAuth** | Same pattern via `ueberauth_apple` → important for iOS |

All methods resolve to the same user via email address. A user can have multiple linked OAuth identities.

### Magic Link Tokens

- Token generated, hashed (SHA-256), stored in `user_tokens` with context `"magic_link"`.
- Plain token sent via email link.
- On click: hash incoming token, match against DB, check expiry, mark used, create session.
- Single-use, time-limited (15 minutes).

### Dual Session Strategy

- **Web (LiveView):** Standard Phoenix session cookie via `phx.gen.auth` pattern — `user_token` in session, `user_tokens` table.
- **Native mobile:** Bearer token in `Authorization` header for API, token in Channel connect params. Same `user_tokens` table, different context (`"api"` vs `"session"`).

### Email Delivery

Swoosh with configurable adapter. Dev: `Swoosh.Adapters.Local` + mailbox viewer at `/dev/mailbox`. Prod: any SMTP/API provider.

---

## 6. Web Interface (`MothWeb` — LiveView)

### Routes

| Route | LiveView | Purpose |
|-------|----------|---------|
| `/` | `HomeLive` | Landing, login entry point |
| `/auth/magic` | `MagicLinkLive` | Email input → "check your inbox" |
| `/auth/callback/:provider` | Controller | OAuth callback, redirects |
| `/game/new` | `Game.NewLive` | Create game — name, prizes, bogey limit, interval |
| `/game/:code` | `Game.PlayLive` | Main game room — ticket, board, chat, claims |
| `/game/:code/host` | `Game.HostLive` | Host controls — start, pause, resume, end |
| `/profile` | `ProfileLive` | Link OAuth accounts, update name |

### `Game.PlayLive` — Core Screen (Mobile-First)

```
┌─────────────────────────┐
│  Game: "Friday Housie"  │  ← game name, status, timer countdown
│  Next pick in: 12s      │
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
│  🏆 Top Line: Priya     │  ← prize feed
│  ❌ Bogey: Raj (2 left) │
├─────────────────────────┤
│  Chat...                 │  ← in-game chat
└─────────────────────────┘
```

### Real-Time Updates

LiveView processes subscribe to `game:CODE:*` PubSub topics on mount. Each game event triggers `handle_info` → update assigns → re-render. Each UI section is a separate LiveComponent for minimal re-rendering.

### Mobile-Friendly

Large tap targets, no hover states, viewport meta tag, Tailwind CSS (ships with Phoenix).

---

## 7. Native Mobile API

### REST Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/api/auth/magic` | Request magic link email |
| `POST` | `/api/auth/verify` | Verify magic link token → bearer token |
| `POST` | `/api/auth/oauth/:provider` | Exchange OAuth code → bearer token |
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

**Auth:** Bearer token in `Authorization` header.

**Error format:** Consistent shape, proper HTTP status codes (401, 403, 404, 422, 429).

```json
{"error": {"code": "invalid_claim", "message": "Numbers not yet picked"}}
```

### Channel (Real-Time for Mobile)

Socket at `/api/socket`, authenticated via bearer token in connect params.

Topic: `"game:CODE"`

Server → Client events mirror the PubSub events (pick, timer, status, player_joined, player_left, prize_claimed, bogey).

Client → Server: Channel is read-only for game events. All actions go through REST. Exception: chat messages go through Channel (`push "message", %{text: "..."}`) since they're high-frequency.

### Rate Limiting

| Scope | Limit |
|-------|-------|
| Auth endpoints | 5 req/min per IP |
| Game creation | 10 req/hour per user |
| Prize claims | 1 req/sec per user per game |
| General API | 60 req/min per user |

ETS-based token bucket, applied at router pipeline level.

---

## 8. Data Model

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
| provider | string | not null ("google", "apple") |
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
| expires_at | utc_datetime | |
| used_at | utc_datetime | single-use magic links |
| inserted_at | utc_datetime | |

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
| snapshot | jsonb | last persisted game state for crash recovery |
| inserted_at | utc_datetime | |
| updated_at | utc_datetime | |

Indexes: on `status`, on `host_id`, unique on `code`.

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
- Timer state
- Real-time player connections (who's currently online)

DB is the recovery path, not the hot path. During active gameplay, all reads come from the GenServer. DB writes happen at: game creation, player join, prize claim, periodic snapshots, game finish.

---

## 9. Scalability & Operations

### Memory Budget (Single 64GB Node)

| Component | Per-unit | At target scale |
|-----------|----------|-----------------|
| GameServer process | ~50KB | 10K × 50KB = ~500 MB |
| LiveView process | ~30KB | 100K × 30KB = ~3 GB |
| Channel process | ~20KB | share of 100K connections |
| ETS caches | — | < 100 MB |
| BEAM overhead | — | ~2-4 GB |

Comfortable headroom on a 64GB node for ~10K games / ~100K players.

### Cluster-Ready Design

| Concern | Single-node | Cluster extension |
|---------|-------------|-------------------|
| Game Registry | Local `Registry` | Swap to `Horde.Registry` |
| Game Supervisor | Local `DynamicSupervisor` | Swap to `Horde.DynamicSupervisor` |
| PubSub | `Phoenix.PubSub` (PG2) | Already distributed across nodes |
| DB | Single Postgres | Same — Ecto pools per node |
| Load balancing | N/A | Sticky sessions by game code |

`Moth.Game` context wraps Registry and DynamicSupervisor calls. Swapping to Horde means changing those wrappers, not game logic.

### Graceful Shutdown

On SIGTERM: stop accepting new connections → broadcast shutdown to all games → persist all snapshots → drain connections → terminate.

### Observability

- `Phoenix.LiveDashboard` for process counts, memory, message queues
- Telemetry events: game created/finished, pick, prize claim, player join/leave, auth
- Structured logging with game_id + user_id for traceability

---

## 10. Project Structure

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
│       └── supervisor.ex        # DynamicSupervisor + Registry setup
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

## 11. Testing Strategy

| Layer | What | How |
|-------|------|-----|
| **Pure functions** | Board, Ticket, Prize, Code | ExUnit. Property-based tests (StreamData) for ticket validity and board exhaustion. |
| **GenServer** | Server lifecycle, state transitions, crash recovery | ExUnit with `start_supervised`. Full lifecycle: lobby → running → pause → resume → finish. Crash + restart from snapshot. |
| **Context integration** | `Moth.Auth`, `Moth.Game` public APIs | ExUnit with Ecto sandbox. Auth flows, game creation, player join, prize claims. |
| **LiveView / API** | Web and mobile interfaces | `Phoenix.LiveViewTest` for web, `Phoenix.ConnTest` for API. Key user flows. |

**Property-based tests:**
- `Ticket.generate/2` always produces valid Tambola tickets
- `Board.pick/1` never repeats, exhausts 1-90
- `Prize.check_claim/3` never validates an incomplete claim

**No mocks.** Real context APIs, real GenServers (`start_supervised`), real DB (Ecto sandbox).

---

## 12. Dependencies

| Dep | Purpose |
|-----|---------|
| `phoenix ~> 1.7` | Web framework |
| `phoenix_live_view ~> 0.20` | Real-time web UI |
| `phoenix_live_dashboard ~> 0.8` | Observability |
| `ecto_sql ~> 3.10` + `postgrex` | Database |
| `swoosh` | Email delivery (magic links) |
| `ueberauth ~> 0.10` | OAuth framework |
| `ueberauth_google ~> 0.12` | Google OAuth |
| `ueberauth_apple ~> 0.x` | Apple OAuth |
| `jason ~> 1.2` | JSON |
| `plug_cowboy ~> 2.5` | HTTP server |
| `dns_cluster ~> 0.1` | Cluster discovery |
| `telemetry_metrics + telemetry_poller` | Observability |
| `esbuild ~> 0.8` | Asset build |
| `tailwind ~> 0.2` | CSS |
| `stream_data` (test only) | Property-based testing |

Drop from POC: `sqids`, `req`, `phoenix_html` (LiveView replaces), `hashids`.

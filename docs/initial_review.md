# Moth — Initial Codebase Review

> **Date:** 2026-04-10
> **Scope:** Full codebase review — architecture, security, efficiency, code quality

---

## Project Overview

**Moth** is an Elixir/Phoenix 1.3 application that hosts real-time **Tambola** (Housie/Bingo) games with WebSocket-based communication. Players join games via Google OAuth, watch numbers being auto-picked at configurable intervals, and compete for prizes. The README claims support for 100K concurrent games and 1M+ users on 16GB RAM.

**Core flow:** OAuth login → Create game (with prizes, moderators, interval) → GenServer auto-picks numbers 1–90 → WebSocket broadcasts picks to all connected players → Moderators award prizes.

### Tech Stack

| Layer | Technology |
|-------|------------|
| Language | Elixir 1.4+ |
| Framework | Phoenix 1.3 |
| Database | PostgreSQL (via Ecto) |
| Real-time | Phoenix Channels (WebSocket), PubSub with PG2 |
| Auth | Ueberauth (Google OAuth), Guardian JWT (beta), Phoenix Token |
| JSON | Poison |
| HTTP Server | Cowboy 1.0 |
| Assets | Brunch, Babel, Phoenix HTML/JS |
| ID Generation | Hashids |

### Architecture

- **Context pattern (DDD):** `Moth.Accounts` (users, credentials) and `Moth.Housie` (games, prizes, servers)
- **OTP processes:** GenServer per game (`Moth.Housie.Server`), Agent per board (`Moth.Housie.Board`)
- **Channels:** `public:lobby` (game listing, unrestricted), `game:{id}` (per-game state, token-gated)
- **Presence:** Phoenix.Presence for live player tracking
- **Plug pipeline:** `SetUser` → `CheckAuth` / `CheckAPIAuth` → `RequireAuth`

---

## What It Gets Right

- **OTP for game state** — GenServer per game + Agent for the number board is idiomatically Elixir and the right model for this domain.
- **Phoenix Channels** — proper use of PubSub and Presence tracking for live player counts.
- **Context pattern** — `Accounts` and `Housie` contexts follow Phoenix 1.3 conventions with clear domain boundaries.
- **Hashid-based game IDs** — short, shareable, non-sequential URLs.
- **Domain fit** — Elixir/BEAM is arguably the best runtime for a massively concurrent real-time game server.

---

## Issues Found

### Summary

| Category | Count | Severity |
|----------|-------|----------|
| Security | 12 | CRITICAL |
| Concurrency / OTP | 6 | HIGH |
| Database Efficiency | 9 | MEDIUM |
| API Design | 5 | MEDIUM |
| Code Quality | 4 | LOW |
| Testing | 2 | LOW |
| Dependencies | 4 | LOW |

---

### 1. Security — CRITICAL

#### S1. Hardcoded `secret_key_base` in version control
- **File:** `config/config.exs:15`
- The `secret_key_base` is hardcoded in source. Anyone with repo access can forge session cookies.

#### S2. Guardian secret falls back to the same hardcoded value
- **File:** `config/config.exs:49`
- `secret_key: System.get_env("GUARDIAN_SECRET") || "<same hardcoded string>"`. If the env var is unset, JWTs are forgeable.

#### S3. Hardcoded session signing salt
- **File:** `lib/moth_web/endpoint.ex:39`
- `signing_salt: "1I015LP/"` — should be generated per deployment.

#### S4. Hardcoded Hashids salt
- **File:** `lib/moth/token.ex:2`
- `@salt "___salt_cant_be_hardcoded_but___"` — the comment says it all. Game IDs become predictable/reversible.

#### S5. WebSocket connect has zero authentication
- **File:** `lib/moth_web/channels/game_socket.ex:23-25`
- `connect/2` unconditionally returns `{:ok, socket}`. Any client can connect. The `public:lobby` channel (`public_channel.ex:4`) accepts anyone with no token check, and `game_channel.ex:26-32` has a fallback that allows joining without a token (`is_admin` becomes false, `user` becomes nil).

#### S6. Open redirect vulnerability
- **File:** `lib/moth_web/controllers/auth_controller.ex:30,38`
- `redirect_url` is read from a cookie (`ui_redirect_url`) and used in `redirect(external: redirect_url)` with zero validation. An attacker can set this cookie to redirect users to a phishing site after OAuth.

#### S7. No CSRF protection on API pipeline
- **File:** `lib/moth_web/router.ex:15-19`
- The `:api` pipeline uses session-based auth (`:fetch_session` + `SetUser`) but omits `:protect_from_forgery`. All state-mutating POST endpoints (`/api/games`, pause, resume, award) are CSRF-vulnerable.

#### S8. No rate limiting
- No rate limiting on login, API endpoints, or WebSocket connections. `POST /api/games` can be abused to spawn unlimited GenServer processes.

#### S9. No input validation on game creation
- **File:** `lib/moth_web/controllers/api/game_controller.ex:18-19`
- `String.to_integer(interval)` crashes on non-numeric input. No bounds checking (0 or negative causes rapid-fire picks; extremely large values stall the game).

#### S10. OAuth tokens stored in plaintext
- **File:** `lib/moth/accounts/credential.ex:8`
- Google OAuth refresh tokens stored as plain strings in the database.

#### S11. `list_users` exposes all users
- **File:** `lib/moth_web/controllers/api/user_controller.ex:4-5`
- Any authenticated user gets the full user list including `google_id` and `avatar_url`. No authorization beyond "is logged in."

#### S12. Unrestricted public channel broadcast
- **File:** `lib/moth_web/channels/public_channel.ex:16-18`
- Any connected client can broadcast arbitrary payloads to all lobby users via `"shout"`. No auth, no rate limit, no payload validation.

---

### 2. Concurrency / OTP — HIGH

#### C1. Game Server processes are NOT supervised
- **File:** `lib/moth/housie/housie.ex:17`
- `Server.start_link(...)` is called directly, not through a DynamicSupervisor. If the server process crashes, the game is gone permanently with no recovery.

#### C2. Pause/resume race condition
- **File:** `lib/moth/housie/server.ex:66-76`
- `pause` cancels the timer, but if the `:update` message is already in the GenServer mailbox, it will still be processed — picking a number and scheduling a new timer after the pause.

#### C3. Double-resume creates parallel timers
- **File:** `lib/moth/housie/server.ex:72-76`
- `resume` creates a new timer without cancelling any existing one. If called twice (TOCTOU race between `is_paused?` check in controller and the `resume` call), two timer chains run in parallel, doubling pick speed.

#### C4. Board Agent operations are not atomic
- **File:** `lib/moth/housie/board.ex:20-29`
- `Board.pick/1` makes four separate Agent calls (bag, picks, count, update). While currently only the GenServer calls it (serialized), the API is public and unprotected against concurrent access.

#### C5. Board crashes on empty bag
- **File:** `lib/moth/housie/board.ex:21`
- `[pick | rest] = bag(board) |> Enum.shuffle` raises `MatchError` if the bag is empty (after 90 picks). If `:update` fires one extra time before state propagates, this crashes the server (unrecoverable per C1).

#### C6. Board Agent leaks on game termination
- **File:** `lib/moth/housie/server.ex:123-126`
- The `terminate` callback does not stop the Board Agent. Every finished game leaves an orphaned Agent process that leaks memory.

---

### 3. Database Efficiency — MEDIUM

#### D1. N+1 preload pattern
- **File:** `lib/moth/housie/housie.ex:31-33, 36-38, 54-57`
- `list_games`, `list_running_games`, and `get_game!` all do `Repo.all` then `Repo.preload([:owner, :moderators, prizes: [:winner]])` — main query + ~4 additional queries. Could be a single join query.

#### D2. Redundant game loads for authorization
- **File:** `lib/moth_web/controllers/api/game_controller.ex:109-113`
- `is_admin?` calls `get_game_admins!` → `get_game!` (full preload including prizes). Then the controller action calls `get_game!` again. Two full game loads per authorized request.

#### D3. Missing index on `games.status`
- **File:** `priv/repo/migrations/20171012165559_add_status_to_game.exs`
- `list_running_games` filters on `status == "running"` but no index exists.

#### D4. Missing index on `games.owner_id`
- **File:** `priv/repo/migrations/20171011160301_create_games.exs`
- Foreign key with no index. Affects owner preloads.

#### D5. Missing index on `users.google_id`
- **File:** `priv/repo/migrations/20171010081644_create_users.exs`
- Logical lookup key with no index.

#### D6. Per-request user DB lookup
- **File:** `lib/moth_web/plug/set_user.ex:14`
- `Repo.get(User, user_id)` on every HTTP and API request (both `:browser` and `:api` pipelines). No caching.

#### D7. N Presence lookups in game index
- **File:** `lib/moth_web/controllers/api/game_controller.ex:10-13`
- `Players.list("game:#{g.id}")` called per running game inside `Enum.reduce`.

#### D8. `get_game_admins!` loads prizes unnecessarily
- **File:** `lib/moth/housie/housie.ex:59-62`
- To check admin status, loads the full game with all preloads including prizes and winners. Only needs `owner` and `moderators`.

#### D9. Channel join triggers query storm
- **File:** `lib/moth_web/channels/game_channel.ex:8-9,18`
- Every channel join: `get_game!` (~5 queries) + `game_state` (GenServer call) + `get_user!` (another query + preload). Many simultaneous joins = query storm.

---

### 4. API Design — MEDIUM

#### A1. Errors returned as 200 OK
- **File:** `lib/moth_web/controllers/api/game_controller.ex:48,64,79,105,117`
- `json conn, %{error: :error, reason: "..."}` returns HTTP 200 with an error body. Only `CheckAPIAuth` correctly uses `put_status(401)`.

#### A2. Inconsistent error response shapes
- Auth controller: `%{status: :error, reason: "..."}`
- Game controller: `%{error: :error, reason: "..."}`
- The `status` vs `error` key inconsistency makes client error handling unreliable.

#### A3. Non-RESTful routes
- **File:** `lib/moth_web/router.ex:32-34`
- `POST /api/games` maps to `:new` instead of `:create`. Pause/resume are RPC-style (`POST /games/:id/pause`) rather than `PATCH /games/:id` with status body.

#### A4. Token generation via GET
- **File:** `lib/moth_web/router.ex:30`
- `GET /api/auth/token` creates a signed token. GET should be safe/idempotent; this should be POST.

#### A5. No pagination
- `list_users/0` and `list_games/0` return all records with no limit/offset.

---

### 5. Code Quality — LOW

#### Q1. Direct Repo calls in controllers
- **File:** `lib/moth_web/controllers/api/game_controller.ex:73,102`
- `Repo.preload` and `Repo.insert!` called directly in the controller, bypassing the Housie context.

#### Q2. No transaction around game + prize creation
- **File:** `lib/moth_web/controllers/api/game_controller.ex:96-103`
- Game is created, then prizes inserted one by one. If a prize insert fails, the game exists with partial prizes and a running GenServer. No `Repo.transaction`.

#### Q3. Three near-identical auth plugs
- `check_api_auth.ex`, `check_auth.ex`, `require_auth.ex` — all check `conn.assigns[:user]`, differing only in response format. Should be one parameterized plug.

#### Q4. Dead code
- **File:** `lib/moth_web/helpers/user_from_auth.ex`
- Entire module is never called from anywhere. The auth controller implements its own user creation logic.

---

### 6. Testing — LOW

#### T1. Auto-generated scaffolding with wrong fixtures
- **File:** `test/moth/accounts/accounts_test.exs:73-74`
- Credential tests reference `google_oauth2_token` field which doesn't exist in the schema. Will fail.
- **File:** `test/moth/housie/housie_test.exs:9-11`
- `@valid_attrs %{}`, `@update_attrs %{}`, `@invalid_attrs %{}` — all empty. Tests pass or fail for wrong reasons.

#### T2. Zero coverage on critical paths
- No tests for: Server, Board, GameChannel, GameSocket, PublicChannel, any controller, any plug, auth flow, prize awarding, pause/resume.

---

### 7. Dependencies — LOW

#### DEP1. Severely outdated stack
- Phoenix `1.3.0` (current: 1.7.x)
- Phoenix PubSub `1.0` (current: 2.x)
- Cowboy `1.0` (current: 2.x)
- Guardian `1.0-beta` (current: 2.x)
- Ueberauth `0.4` (current: 0.10.x)
- `ja_serializer ~> 0.12` — abandoned (last release 2019)
- `fs` pulled from GitHub with no version pin

#### DEP2. Poison instead of Jason
- **File:** `lib/moth_web/endpoint.ex:28`
- Phoenix ecosystem has moved to Jason, which is significantly faster.

#### DEP3. Compile-time `Application.get_env`
- **File:** `lib/moth_web/controllers/auth_controller.ex:4`
- `@hosted_domains Application.get_env(...)` is evaluated at compile time. Config changes require recompilation. Known Elixir anti-pattern.

#### DEP4. Repo.init unconditionally overrides with DATABASE_URL
- **File:** `lib/moth/repo.ex:9`
- `Keyword.put(opts, :url, System.get_env("DATABASE_URL"))` — if DATABASE_URL is unset, this puts `nil`, potentially overriding valid config.

---

## Efficiency Bottleneck Summary

| Bottleneck | Location | Impact |
|------------|----------|--------|
| Per-request user DB lookup | `plug/set_user.ex:14` | Every HTTP/API/WebSocket request hits the DB |
| Double game load for auth | `game_controller.ex:109-113` | 2x full preload per authorized action |
| `Enum.shuffle` entire bag every pick | `board.ex:21` | Unnecessary allocation every second per active game |
| N Presence lookups in game index | `game_controller.ex:10-13` | Linear with running game count |
| 24-hour zombie processes | `server.ex:9` | Finished games linger as live processes |
| Orphaned Board Agents | `server.ex:123-126` | Memory leak per finished game |

---

## Recommended Fix Priority

| # | Priority | Issue | Effort |
|---|----------|-------|--------|
| 1 | CRITICAL | Move all secrets to env vars, rotate them | Low |
| 2 | CRITICAL | Validate/whitelist `ui_redirect_url` cookie | Low |
| 3 | CRITICAL | Add CSRF protection or switch API to token-based auth | Medium |
| 4 | HIGH | Supervise game Servers with DynamicSupervisor | Medium |
| 5 | HIGH | Fix pause/resume race (move checks inside GenServer) | Medium |
| 6 | HIGH | Wrap game+prize creation in Repo.transaction | Medium |
| 7 | HIGH | Stop Board Agent in Server terminate callback | Low |
| 8 | MEDIUM | Add indexes on `games.status`, `games.owner_id`, `users.google_id` | Low |
| 9 | MEDIUM | Return proper HTTP status codes (401, 403, 404, 422) | Medium |
| 10 | MEDIUM | Cache user lookups or move to stateless token auth | Medium |
| 11 | MEDIUM | Consolidate auth plugs | Low |
| 12 | LOW | Upgrade Phoenix to 1.7, replace Poison with Jason, upgrade Guardian | High |
| 13 | LOW | Add WebSocket authentication in `connect/2` | Medium |
| 14 | LOW | Write real tests for Server, Board, Channels, Controllers | High |

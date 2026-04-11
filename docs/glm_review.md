# Moth — GLM Codebase Review

> **Date:** 2026-04-10
> **Scope:** Full codebase review — architecture, security, gameplay, code quality
> **Reviewer:** GLM (via Crush)

---

## Architecture & Design — Strong Foundation

The v2 rewrite is a **massive improvement** over v1. The architecture is idiomatic Elixir/OTP:
- GenServer-per-game under DynamicSupervisor with Registry is the right model
- Write-through for player joins + periodic snapshots for board state is a reasonable persistence strategy
- Context separation (`Moth.Game`, `Moth.Auth`) is clean
- The codebase is small, readable, and focused

---

## Critical Issues

### 1. Late-joiner exploit remains unfixed
`Server.join/2` allows players to join *after* the game starts (`lib/moth/game/server.ex:87-103`). The `agent_spec_review.md` already flags this — a sniper can wait until 70 numbers are picked, then join with throwaway accounts to claim unclaimed prizes with high statistical probability. **Fix: disallow joins after `:running`.**

### 2. GenServer mailbox exhaustion (DoS)
Chat rate-limiting (1/sec) is enforced *inside* the GameServer (`server.ex:162-170`), not at the edge. A bot sending 10K chat messages/sec fills the GenServer mailbox before the rate limit ever fires, blocking prize claims and game actions. **Fix: rate-limit in LiveView/Channel before forwarding to GameServer.**

### 3. Thundering herd on supervisor restart
The spec review identifies this but it's not fixed. If the Registry crashes, `rest_for_one` kills all GameServers. On restart, 10K servers simultaneously hit Postgres in `init/1`. **Fix: add jitter in init or staggered restart.**

### 4. `secret_key_base` hardcoded in dev.exs
`config/dev.exs:7` has a real secret in source control. While dev-only, it's a bad habit and could leak into prod configs. **Fix: `System.get_env("SECRET_KEY_BASE") || "dev-only-..."` with a clearly fake default.**

### 5. `String.to_existing_atom/1` on user input
`game_controller.ex:80` calls `String.to_existing_atom(prize)` on API input. While `to_existing_atom` won't create new atoms (it raises instead), the error isn't handled gracefully — it crashes the controller process. **Fix: wrap in try/rescue or validate against a whitelist.**

---

## High-Priority Issues

### 6. No game player limit
`create_game` and `join_game` have no maximum player count. A single game with 100K players would OOM the GenServer. **Fix: add `max_players` to settings (default ~100).**

### 7. Host disconnect keepalive exploit
`server.ex:175-177`: Host disconnects → 60s timer → auto-pause. The spec review notes a host can disconnect/reconnect every 29 minutes to keep the game alive forever. **Fix: absolute max game lifetime.**

### 8. Snapshot every 5 picks is insufficient
If the server crashes at pick 14, it restores from the snapshot at pick 10. Prize claims (write-through) at picks 12-14 are in DB but not on the board. This creates the "time travel" inconsistency the agent review documents. **Fix: write-through on every pick (1K writes/sec is trivial for Postgres).**

### 9. Missing `game_players.user_id` index
The migration creates a composite index on `(game_id, user_id)` but not a standalone `user_id` index. Querying "my games" does a sequential scan. **Fix: `create index(:game_players, [:user_id])`.**

### 10. Monitor reaper calls `:state` on every game every minute
`monitor.ex:44`: `GenServer.call(pid, :state, 5_000)` on every active game. At 10K games, that's 10K synchronous calls per minute. **Fix: track status in Registry metadata, avoid calling into each GenServer.**

---

## Medium Issues

### 11. `Board.from_snapshot/1` doesn't restore picks correctly
`board.ex:37-41`: `picks` field stores picks in reverse order (`[number | picks]`), but `from_snapshot` uses the raw list from JSON. After restore, `picks` order is wrong — the most recently picked number should be at the head, but JSON serialization doesn't guarantee this.

### 12. No CORS configuration for production
`router.ex:16`: `CORSPlug` is in the API pipeline but there's no CORS config in `config.exs` or `runtime.exs`. Defaults may be too permissive or too restrictive.

### 13. Auto-strike uses `GenServer.call` (thundering herd)
`play_live.ex:122`: When 100+ players have auto-strike enabled, each pick triggers 100+ synchronous `GenServer.call`s to the GameServer. **Fix: use `GenServer.cast` for auto-strike (already noted in the frontend spec).**

### 14. Ticket `from_map/1` doesn't validate structure
Prize validation (`prize.ex:15-17`) pattern matches on `rows` as a list of 3 elements, but `Ticket.from_map` doesn't validate structure. If the DB-stored ticket is corrupted, prize checks silently fail or crash.

### 15. `sanitize_state/1` leaks internal IDs
`server.ex:198`: Returns `id` (DB record ID) and `host_id` in the public state. Host user ID shouldn't be exposed to all players.

---

## Low-Priority / Code Quality

- **README is stale**: Still references npm/brunch, says nothing about the v2 stack (esbuild, tailwind, LiveView).
- **`api.md` is entirely outdated**: Documents v1 routes that no longer exist.
- **Empty `Moth` module**: `lib/moth.ex` is just a docstring placeholder.
- **No `phx.gen.auth`**: Custom auth is fine, but it misses standard features like password reset, email confirmation.
- **Test coverage gaps**: No LiveView tests, no Channel tests, no integration tests for the full game lifecycle (create → join → start → pick → claim → finish).
- **Old migrations left in tree**: 8 v1 migrations from 2017 coexist with the v2 drop-and-recreate migration. Clean migration history would be better for a fresh start.
- **`viewport` meta disables zoom**: `root.html.heex:7`: `maximum-scale=1, user-scalable=no` — the frontend spec explicitly calls for removing this (accessibility concern), but it's still there.
- **`Code` module word list has duplicate "WINTER"**: Appears at positions 37 and 186 in `@words`. Minor but reduces code space.

---

## What's Good

- Clean separation of concerns: `Board`, `Ticket`, `Prize`, `Code` are pure modules with no side effects — highly testable
- Proper use of Registry for game lookup
- Token-based API auth with SHA256 hashing and expiry
- The `DevAuth` plug is a nice DX touch
- Property-based tests for Board and Ticket
- The concurrent claims test in `server_test.exs` is excellent

---

## Verdict

The v2 codebase is a **solid 7/10** — architecturally sound with good OTP patterns, but has several security/exploitation gaps (late join, DoS via mailbox, keepalive exploit) that need fixing before production. The most impactful work is: (1) lock joins after game start, (2) move rate limits to the edge, (3) write-through every pick, (4) add jitter for crash recovery.

---

## Recommended Fix Priority

| # | Priority | Issue | Effort |
|---|----------|-------|--------|
| 1 | CRITICAL | Lock joins after game starts | Small |
| 2 | CRITICAL | Move chat rate limits to LiveView/Channel edge | Medium |
| 3 | CRITICAL | Add jitter for supervisor restart thundering herd | Small |
| 4 | CRITICAL | Move secrets out of source control | Low |
| 5 | HIGH | Validate `String.to_existing_atom` input gracefully | Low |
| 6 | HIGH | Add `max_players` to game settings | Small |
| 7 | HIGH | Enforce absolute max game lifetime | Small |
| 8 | HIGH | Write-through every pick to DB instead of every 5 | Small |
| 9 | HIGH | Add `game_players.user_id` index | Low |
| 10 | MEDIUM | Track status in Registry metadata for Monitor | Medium |
| 11 | MEDIUM | Fix `Board.from_snapshot` picks order | Small |
| 12 | MEDIUM | Configure CORS for production | Low |
| 13 | MEDIUM | Use `GenServer.cast` for auto-strike | Trivial |
| 14 | MEDIUM | Validate ticket structure in `from_map` | Small |
| 15 | LOW | Remove `host_id` from public state | Trivial |
| 16 | LOW | Update README and api.md | Low |
| 17 | LOW | Remove duplicate WINTER from code word list | Trivial |
| 18 | LOW | Remove `user-scalable=no` from viewport meta | Trivial |
| 19 | LOW | Clean up v1 migration history | Low |
| 20 | LOW | Add LiveView and integration tests | High |

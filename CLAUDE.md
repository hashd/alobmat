# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

**Moth** is a real-time multiplayer Tambola (Indian bingo/housie) game server. One GenServer process per active game, capable of hosting 100k+ concurrent games on a single machine. The backend is Elixir/Phoenix; the frontend is a Vue 3 + TypeScript + Pinia + Vite SPA communicating via Phoenix Channels.

## Commands

```bash
# Initial setup
mix setup                          # deps.get + ecto.setup + assets.setup

# Development
mix phx.server                     # starts Phoenix on :4000 + Vite dev server on :5173
iex -S mix phx.server              # same, with interactive shell

# Database
mix ecto.migrate                   # run pending migrations
mix ecto.reset                     # drop + recreate + seed

# Backend tests
mix test                           # all tests (also runs ecto.create + migrate)
mix test test/moth/game/server_test.exs                    # single file
mix test test/moth/game/server_test.exs:42                 # single test by line
mix test --only game                                        # by tag

# Frontend tests
cd assets && npx vitest run        # all frontend unit tests
cd assets && npx vitest            # watch mode
cd assets && npx tsc --noEmit      # TypeScript strict check

# Assets
cd assets && npm run build         # production build → priv/static/
```

## Architecture

### Game engine (pure Elixir, no web)

`lib/moth/game/` contains the entire game engine:

- **`game.ex`** — public context API. All callers go through here, never directly to `Server`.
- **`server.ex`** — one `GenServer` per active game. Holds all in-memory game state (board, tickets, struck numbers, prizes, bogeys, chat rate-limits). Broadcasts state changes via `Phoenix.PubSub` as `{event_atom, payload_map}` tuples on topic `"game:#{code}"`.
- **`supervisor.ex`** — `rest_for_one` tree: `Registry` → `DynSup` (hosts all Server processes) → `Monitor` (cleans up dead game processes).
- **`monitor.ex`** — watches Server PIDs via `Process.monitor`; cleans up Registry + DB record on crash.
- **`board.ex`**, **`ticket.ex`**, **`prize.ex`** — pure data modules. `Board.to_map/1` and `Ticket.to_map/1` produce JSON-serializable maps.

Game lookup: `Registry.lookup(Moth.Game.Registry, code)` → PID. `Game.with_server/2` wraps this and returns `{:error, :game_not_found}` if the process isn't alive.

### Auth

`lib/moth/auth/` — three token contexts in `UserToken`:
- `"session"` — cookie-based, used by the browser `AuthController`
- `"api"` — bearer token (30-day validity), used by `MothWeb.Plugs.APIAuth` and all `/api/*` routes, and by `UserSocket` for channel auth
- `"magic_link"` — 15-minute single-use token for passwordless login

`Moth.Auth` is the context module wrapping all token ops. `MothWeb.Plugs.Auth` reads session cookies; `MothWeb.Plugs.APIAuth` reads `Authorization: Bearer <token>` headers.

In dev, `MothWeb.Plugs.DevAuth` provides passwordless local login (enabled via `:dev_routes` compile env).

### Real-time layer (Phoenix Channels)

- **`user_socket.ex`** — authenticates via bearer token (`Moth.Auth.get_user_by_api_token/1`). Routes `"game:*"` to `GameChannel`.
- **`channels/game_channel.ex`** — one channel process per player per game. On join: calls `Game.join_game` (idempotent), subscribes to PubSub topic `"game:#{code}"` and presence topic `"game:#{code}:presence"`, enriches player data with names/prizes/bogeys. Translates 8 PubSub events to JSON channel pushes. Handles 4 inbound messages (strike, claim, chat, reaction). `terminate/2` calls `Game.player_left/2` on disconnect.
- **`presence.ex`** — wraps `Phoenix.Presence` on topic `"game:#{code}:presence"`. Channel subscribes to this topic and forwards `presence_diff` events to clients.

### Web layer

`lib/moth_web/` — standard Phoenix structure:
- `router.ex` — three scopes: `/api` (unauthenticated), `/api` + `:require_api_auth` (authenticated REST), `:browser` (OAuth callbacks + SPA catch-all)
- `controllers/api/` — JSON controllers for auth, user, game actions
- `controllers/page_controller.ex` — `spa` action serves `priv/static/index.html`
- `controllers/auth_controller.ex` — OAuth callback and magic link verify both redirect to `/#/auth/callback?token=<bearer_token>`

### Frontend (Vue SPA)

`assets/js/` — Vue 3 + TypeScript + Pinia + Vite:

- **`app.ts`** — entry point, creates Pinia + Vue app, mounts router
- **`router.ts`** — hash-based routing with `beforeEach` auth guard
- **`types/`** — `domain.ts` (User, Player, Ticket, Board, etc.), `channel.ts` (GameJoinReply, event types), `phoenix.d.ts` (type shim)
- **`api/client.ts`** — typed fetch wrapper for all REST endpoints
- **`stores/`** — Pinia stores: `auth` (login/logout/token), `theme` (light/dark/system), `game` (full game state + event handlers), `chat` (activity feed with 50-entry cap), `presence` (online players)
- **`composables/`** — `useChannel` (Phoenix socket/channel wiring to stores), `useCountdown`, `useConfetti`, `useAutoScroll`
- **`components/ui/`** — Button, Card, Avatar, Badge, Modal, Toast, InputField, SegmentedControl, BottomSheet, ConnectionStatus
- **`components/game/`** — TicketGrid, Board, CountdownRing, ActivityFeed, ReactionOverlay
- **`pages/`** — Auth, Home, Profile, NewGame, GamePlay, HostDashboard

## Key conventions

- Game codes are uppercase strings generated by `Game.Code` using Hashids, guaranteed unique against currently-running games via Registry.
- Prize names are atoms: `:early_five`, `:top_line`, `:middle_line`, `:bottom_line`, `:full_house`. Stored as atoms in GenServer state and as strings in the DB and channel JSON.
- `strike_out_async` (cast) vs `strike_out` (call) — use async from channel handlers to avoid blocking.
- Test fixtures live in `test/support/`. The `mix test` alias auto-creates and migrates the test DB.
- Frontend uses `@` alias for `assets/js/` in imports.
- CSS custom properties (`--bg`, `--accent`, `--border`, `--text-primary`, etc.) drive theming.

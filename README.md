# Moth (Alobmat)

A real-time multiplayer Tambola (Indian bingo/housie) game server. One GenServer process per active game, capable of hosting 100k+ concurrent games on a single machine.

**Backend:** Elixir/Phoenix, Phoenix Channels, Phoenix Presence
**Frontend:** Vue 3, TypeScript, Pinia, Vite, Tailwind CSS

## Prerequisites

- [Erlang/OTP](http://www.erlang.org) 27+
- [Elixir](http://elixir-lang.org) 1.18+
- [Node.js](https://nodejs.org) 20+ and npm
- [PostgreSQL](https://www.postgresql.org) 15+

## Setup

```bash
# Clone and setup
git clone <repo-url> && cd alobmat
mix setup                          # deps.get + ecto.setup + assets.setup

# Start development server
mix phx.server                     # Phoenix on :4000, Vite on :5173
```

Visit [localhost:4000](http://localhost:4000) in your browser.

## Architecture

### Game Engine

Pure Elixir — no web dependency. One `GenServer` per active game holds all in-memory state (board, tickets, struck numbers, prizes, bogeys). State changes are broadcast via `Phoenix.PubSub` as `{event_atom, payload}` tuples.

### Real-time Communication

Phoenix Channels provide the real-time layer:
- **UserSocket** authenticates via bearer token
- **GameChannel** translates PubSub events to JSON pushes, handles player actions (strike, claim, chat, reaction)
- **Presence** tracks online players per game

### Frontend

Vue 3 SPA with hash-based routing:
- **Pinia stores** manage auth, theme, game state, chat, and presence
- **`useChannel` composable** wraps the Phoenix socket/channel lifecycle
- **Pages:** Auth, Home, Profile, NewGame, GamePlay, HostDashboard

### Auth

- Google OAuth (redirects with bearer token)
- Magic link email (passwordless login)
- Bearer tokens for API + WebSocket auth

## Commands

```bash
# Development
mix phx.server                     # start everything
iex -S mix phx.server              # with interactive shell

# Backend tests
mix test                           # 79 tests + property tests
mix test test/moth/game/server_test.exs     # single file

# Frontend tests
cd assets && npx vitest run        # unit tests
cd assets && npx tsc --noEmit      # type check

# Production build
cd assets && npm run build         # outputs to priv/static/
```

## Configuration

Environment variables for OAuth:

```bash
GOOGLE_CLIENT_ID=your-client-id
GOOGLE_CLIENT_SECRET=your-client-secret
```

Database config is in `config/dev.exs` (defaults to `postgres:postgres@localhost/moth_dev`).

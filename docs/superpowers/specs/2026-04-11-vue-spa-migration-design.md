# Vue SPA Migration Design

**Date:** 2026-04-11
**Status:** Approved (v2 — post adversarial review)
**Author:** Kiran Danduprolu

## Background

The current Moth app uses Phoenix LiveView for server-side rendering. This has caused significant developer experience friction and bugs when using AI tooling to implement UI changes — HEEX templates and LiveView's state model are not well-supported by AI coding tools. The decision was made to replace the entire frontend with a Vue 3 SPA.

## Goal

Replace all LiveView/HEEX frontend code with a Vue 3 + TypeScript + Pinia + Vite SPA. The Phoenix/Elixir backend is largely preserved, but **significant backend changes are required** — specifically building the Phoenix Channels layer and adapting the OAuth callback for token-based auth.

## Approach

**Full SPA migration** — all 6 LiveView routes are removed. Phoenix serves a single `index.html` via a catch-all route. Vue Router handles all client-side navigation. No gradual migration, no mixed HEEX/Vue coexistence.

Rationale: a partial migration still leaves HEEX in the codebase, which doesn't solve the DX problem. The app has only 6 pages and the backend API endpoints largely exist, making a full migration feasible.

## Phased Execution

The implementation is split into two phases with a clear handoff. The backend Channel layer blocks all frontend real-time work.

**Phase 1 — Backend (blocks Phase 2)**
- Build `UserSocket` + `GameChannel` (the entire real-time transport layer)
- Fix OAuth callback to return tokens instead of session cookies
- Add missing API endpoints (`GET /api/games`, `POST /api/games/:code/clone`)

**Phase 2 — Frontend**
- Vue SPA: router, stores, composables, pages, components
- Requires a working `GameChannel` to connect to

## Architecture

```
Browser (Vue SPA)
├── Vue Router       — client-side routing
├── Pinia Stores     — app state (auth, game, chat, theme, presence)
├── Vue SFCs         — pages and components
└── useChannel       — Phoenix WebSocket via phoenix.js

        ↕ HTTP (fetch)        ↕ WebSocket
Phoenix (Elixir Backend)
├── REST API (/api/*)         — auth, user, game CRUD
├── Phoenix Channels          — real-time game events (NEW)
├── Game GenServer            — state machine (untouched)
└── Static serving            — priv/static (Vite output)
```

### Build pipeline

Vite replaces esbuild. Assets live in `assets/`, Vite builds to `priv/static/`. In development, Phoenix spawns Vite as a child watcher. Vite's dev server proxies `/api` and `/socket` back to Phoenix on port 4000.

Full `vite.config.ts`:
```typescript
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'

export default defineConfig({
  plugins: [vue()],
  root: 'assets',
  build: {
    outDir: '../priv/static',
    emptyOutDir: true,
    manifest: true,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'assets/js'),
    },
  },
  server: {
    port: 5173,
    proxy: {
      '/api': { target: 'http://localhost:4000', changeOrigin: true },
      '/socket': { target: 'ws://localhost:4000', ws: true },
    },
  },
})
```

Note: in dev, the browser hits the Vite dev server on port 5173 for HMR and the proxy handles API/WebSocket traffic. Phoenix is not the browser's origin in dev; it is in production.

### Real-time

Phoenix Channels handle all real-time communication. The `useChannel` composable wraps `phoenix.js` Socket + Channel, joins `game:<code>` on mount, routes incoming events to Pinia store actions, and leaves on unmount.

**Reconnection strategy:** `phoenix.js` Socket auto-reconnects. On channel rejoin after reconnect, `gameStore.join()` is called again to re-fetch full game state from the server and overwrite stale store state. The `channelConnected` flag is set to `false` while disconnected; the UI shows a reconnecting indicator.

## Authentication

The current app uses Phoenix cookie-based sessions (set server-side by LiveView). A Vue SPA cannot use these directly. Authentication switches to **token-based** (Phoenix-signed tokens via `UserToken`):

1. **Magic link flow:** User requests link via `POST /api/auth/magic` → clicks emailed link → `GET /api/auth/magic/verify?token=<token>` returns a signed API token → stored in `authStore` (localStorage) → sent as `Authorization: Bearer <token>` header on all API requests and as `{ token }` connect param on the Phoenix Channel socket.

2. **OAuth (Google):** SPA links to `/auth/google` → Ueberauth redirects to Google → Phoenix `AuthController.callback` **[BACKEND CHANGE REQUIRED]** must be modified to: generate an API token via `Auth.generate_api_token(user)`, then redirect to `/#/auth/callback?token=<token>` instead of setting a session cookie. Currently the callback calls `AuthPlug.log_in_user/2` which sets a cookie — this must be changed.

3. **Token refresh:** Tokens have a fixed expiry. `authStore` checks expiry on app boot and before game-critical actions. If within 10 minutes of expiry, calls `POST /api/auth/refresh`. If already expired (refresh returns 401), the user is redirected to `/auth` to re-authenticate. Note: the `/api/auth/refresh` endpoint reads from `conn.assigns.current_user` which is `nil` for expired tokens — users with expired tokens must re-authenticate via magic link or OAuth.

4. **Channel auth:** `useChannel` passes `{ token }` as connect params when opening the Phoenix Socket. The `UserSocket.connect/3` callback verifies the token. If invalid/expired, the socket connection is rejected and the user is redirected to `/auth`.

5. **Existing browser-scope `AuthController`** remains but its `callback` action is modified to return tokens for SPA OAuth. The `/:provider` redirect flow stays unchanged; only the callback response changes.

## File Structure

```
assets/
├── index.html                ← Vite entry point
├── vite.config.ts
├── tsconfig.json
├── package.json              ← NEW: required for npm deps (phoenix, @vitejs/plugin-vue, etc.)
└── js/
    ├── app.ts                ← mounts Vue app
    ├── router.ts             ← Vue Router
    ├── types/
    │   ├── domain.ts         ← User, Player, GameSettings, GameStatus, Ticket, Theme
    │   └── channel.ts        ← all Channel event types (inbound + outbound)
    ├── stores/
    │   ├── auth.ts           ← user, token, login/logout/updateProfile
    │   ├── game.ts           ← full game state, channel event handlers
    │   ├── chat.ts           ← chat messages, activity feed entries
    │   ├── theme.ts          ← light/dark/system, localStorage persistence
    │   └── presence.ts       ← player presence map, syncPresence()
    ├── composables/
    │   ├── useChannel.ts     ← Phoenix Socket + Channel wrapper (injectable for testing)
    │   ├── useCountdown.ts   ← timer countdown (replaces Countdown hook)
    │   ├── useConfetti.ts    ← celebration animation (replaces Confetti hook)
    │   └── useAutoScroll.ts  ← chat/feed auto-scroll (replaces AutoScroll hook)
    ├── api/
    │   └── client.ts         ← typed fetch wrapper (auth, user, game endpoints)
    ├── pages/
    │   ├── Home.vue
    │   ├── GamePlay.vue
    │   ├── HostDashboard.vue
    │   ├── Profile.vue
    │   ├── NewGame.vue
    │   └── Auth.vue
    └── components/
        ├── ui/               ← Button, Card, Avatar, Badge, Modal, Toast, InputField,
        │                       SegmentedControl, BottomSheet, ConnectionStatus
        └── game/             ← TicketGrid, Board, CountdownRing, ActivityFeed,
                                ReactionOverlay
```

All `.vue` files use `<script setup lang="ts">`.

## Pinia Stores

### authStore
- **State:** `user: User | null`, `token: string | null`, `tokenExpiresAt: Date | null`
- **Actions:** `login(token, expiresAt)`, `logout()`, `refreshToken()`, `updateProfile()`
- **Persistence:** token + expiry stored in localStorage; checked on app boot

### gameStore
- **State:**
  - `code: string`, `name: string`, `status: GameStatus`, `settings: GameSettings`
  - `board: { picks: number[]; count: number; finished: boolean }`
  - `myTicket: Ticket`, `myStruck: Set<number>`
  - `players: Player[]`
  - `prizes: Record<string, PrizeStatus>` — where `PrizeStatus = { claimed: boolean; winner_id: string | null }`
  - `prizeProgress: Record<string, Record<string, number>>` — per-player prize proximity (host dashboard leaderboard)
  - `nextPickAt: string | null`, `channelConnected: boolean`
- **Actions:** `join()`, `strike(number)`, `claimPrize(prize: string)`, `sendReaction(emoji: string)`
- **Channel handlers (inbound):** `onPick`, `onPresence`, `onReaction`, `onStatusChange`, `onPrizeClaimed`, `onBogey`, `onPlayerJoined`, `onPlayerLeft`, `onStrikeResult`

### chatStore
- **State:** `messages: ChatEntry[]`, `filter: 'all' | 'chat' | 'events'`
- **Actions:** `sendChat(text: string)`, `addEntry(entry: ActivityEntry)`, `setFilter(f)`
- **Channel handlers:** `onChat`, `onBogey` (adds activity entry), `onPrizeClaimed` (adds activity entry), `onPick` (adds activity entry)
- Capped at 50 entries (mirrors current LiveView stream limit)

### themeStore
- **State:** `theme: Theme`
- **Actions:** `toggle()`, `setTheme(theme)`
- **Side effect:** syncs `dark` class to `<html>`, persists to localStorage

### presenceStore
- **State:** `players: Map<string, PresenceMeta>`
- **Actions:** `syncPresence(diff: PresenceDiff)`

## TypeScript Types

### types/domain.ts
```typescript
interface User {
  id: string
  name: string
  email: string
  avatar_url: string | null
}

interface Player {
  user_id: string
  name: string
  prizes_won: string[]
  bogeys: number
}

interface GameSettings {
  interval: number
  bogey_limit: number
  enabled_prizes: string[]
}

// Matches Ticket.to_map/1 in lib/moth/game/ticket.ex
interface Ticket {
  rows: (number | null)[][]  // 3×9 grid, null = blank cell
  numbers: number[]           // flat list of numbers on this ticket
}

// Matches Board.to_map/1 in lib/moth/game/board.ex
interface Board {
  picks: number[]
  count: number
  finished: boolean
}

interface PrizeStatus {
  claimed: boolean
  winner_id: string | null
}

type GameStatus = 'lobby' | 'running' | 'paused' | 'finished'
type Theme = 'light' | 'dark' | 'system'

interface ChatEntry {
  id: string
  type: 'chat' | 'pick' | 'prize_claimed' | 'bogey' | 'system'
  user_id?: string
  user_name?: string
  text?: string
  number?: number
  prize?: string
  timestamp: string
}
```

### types/channel.ts

All event names are the strings used on the wire (Phoenix Channel topic).

```typescript
// ─── Server → Client (inbound) ───────────────────────────────────────────────

// Matches server.ex pick broadcast: { number, count, next_pick_at, server_now }
interface NumberPickedEvent {
  number: number
  count: number
  next_pick_at: string
  server_now: string
}

interface GameStatusEvent {
  status: GameStatus
}

// Sent to ALL subscribers when a prize is claimed
interface PrizeClaimedEvent {
  prize: string
  winner_id: string
  winner_name: string
}

// Sent ONLY to the claiming socket on bogey/rejection
interface ClaimRejectionEvent {
  reason: 'bogey' | 'already_claimed' | 'disqualified' | 'invalid'
  bogeys_remaining?: number
}

// Sent to the striking socket to confirm or reject an optimistic strike
interface StrikeResultEvent {
  number: number
  result: 'ok' | 'rejected'
}

interface BogeyEvent {
  user_id: string
  bogeys_remaining: number
}

interface ChatEvent {
  id: string
  user_id: string
  user_name: string
  text: string
  timestamp: string
}

interface ReactionEvent {
  emoji: string
  user_id: string
}

interface PlayerJoinedEvent {
  user_id: string
  name: string
}

interface PlayerLeftEvent {
  user_id: string
}

interface PresenceMeta {
  name: string
  online_at: string
}

interface PresenceDiff {
  joins: Record<string, PresenceMeta>
  leaves: Record<string, PresenceMeta>
}

// Initial state sent as join reply when a client joins the channel
interface GameJoinReply {
  code: string
  name: string
  status: GameStatus
  settings: GameSettings
  board: Board
  players: Player[]
  prizes: Record<string, PrizeStatus>
  prize_progress: Record<string, Record<string, number>>
  my_ticket: Ticket
  my_struck: number[]
}

// ─── Client → Server (outbound) ──────────────────────────────────────────────

interface StrikeMessage { number: number }
interface ClaimMessage { prize: string }
interface ReactionMessage { emoji: string }
interface ChatMessage { text: string }
```

## Vue Router

```
/                    → Home.vue           (public)
/auth                → Auth.vue           (public — magic link + OAuth callback)
/profile             → Profile.vue        (requires auth)
/game/new            → NewGame.vue        (requires auth)
/game/:code          → GamePlay.vue       (requires auth — joins game on mount)
/game/:code/host     → HostDashboard.vue  (requires auth + must be game host)
```

Navigation guards enforce requirements using `authStore`. Unauthenticated access to protected routes redirects to `/auth?redirect=<original_path>`.

**Hard refresh:** Phoenix's SPA catch-all route ensures any URL returns `index.html` on hard refresh. Vue Router then handles routing client-side.

## useChannel Composable

```typescript
// Injectable socket factory — pass a mock in tests
type SocketFactory = (token: string) => Socket

function useChannel(code: string, socketFactory?: SocketFactory) {
  // defaults to real phoenix.js Socket if no factory provided
}
```

On mount:
1. Opens Socket with `{ params: { token: authStore.token } }`
2. Joins `game:<code>` channel
3. Sends `join` → receives `GameJoinReply` → calls `gameStore.hydrate(reply)`
4. Registers all inbound event handlers routing to store actions

On reconnect (socket `onOpen` after disconnect):
1. Re-joins `game:<code>`
2. Re-fetches full state via `GameJoinReply`
3. Sets `gameStore.channelConnected = true`

On unmount: leaves channel, disconnects socket.

## Phoenix Changes

### New: lib/moth_web/user_socket.ex
```elixir
defmodule MothWeb.UserSocket do
  use Phoenix.Socket

  channel "game:*", MothWeb.GameChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Moth.Auth.verify_api_token(token) do
      {:ok, user} -> {:ok, assign(socket, :current_user, user)}
      {:error, _} -> :error
    end
  end

  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
```

### New: lib/moth_web/channels/game_channel.ex

Handles all real-time game communication.

**On join (`"game:<code>"`):**
- Verifies game exists and user has access
- Calls `MothWeb.Presence.track(self(), ...)` to register presence
- Subscribes to PubSub topic `"game:<code>"` to receive Game.Server broadcasts
- Replies with full `GameJoinReply` payload (code, board, ticket, struck, prizes, prize_progress, players, status, settings)

**Inbound messages (client → server):**
- `"strike"` → calls `Game.strike_out(code, user_id, number)` → pushes `StrikeResultEvent` back to socket
- `"claim"` → calls `Game.claim_prize(code, user_id, prize)` → on success broadcasts `PrizeClaimedEvent`; on failure pushes `ClaimRejectionEvent` to the claiming socket only
- `"reaction"` → broadcasts `ReactionEvent` to all channel subscribers
- `"chat"` → broadcasts `ChatEvent` to all channel subscribers

**Outbound broadcasts (PubSub → Channel → client):**

The Game.Server broadcasts raw Elixir tuples via `Phoenix.PubSub.broadcast`. The GameChannel subscribes to the same topic and translates these to JSON-serializable Channel pushes:

| PubSub tuple | Channel event | Notes |
|---|---|---|
| `{:pick, payload}` | `"number_picked"` | Rename `count`, drop internal fields |
| `{:status, status}` | `"status_changed"` | Atom → string |
| `{:prize_claimed, payload}` | `"prize_claimed"` | Broadcast to all |
| `{:bogey, payload}` | `"bogey"` | Broadcast to all |
| `{:player_joined, payload}` | `"player_joined"` | Include name |
| `{:player_left, payload}` | `"player_left"` | Include user_id |
| `{:chat, payload}` | `"chat"` | Broadcast to all |
| `{:reaction, payload}` | `"reaction"` | Broadcast to all |

**Presence:** Uses `MothWeb.Presence.track(socket, ...)` — existing `Presence` module must be adapted to accept a channel socket instead of a LiveView PID. The topic `"game:<code>:presence"` stays the same.

### Modified: lib/moth_web/endpoint.ex
Add UserSocket before the LiveView socket:
```elixir
socket "/socket", MothWeb.UserSocket,
  websocket: true,
  longpoll: false
```

### Modified: lib/moth_web/controllers/auth_controller.ex (OAuth callback)
The `callback/2` action must be changed to support SPA clients:
```elixir
def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
  user = # ... find or create user from auth
  {:ok, token, expires_at} = Moth.Auth.generate_api_token(user)
  redirect(conn, to: "/#/auth/callback?token=#{token}&expires_at=#{expires_at}")
end
```

### Modified: lib/moth_web/router.ex
- Remove all `live` routes
- Keep all `/api/*` routes unchanged
- Add new API endpoints (see below)
- Add SPA catch-all (must come last): `get "/*path", PageController, :spa`

### New/Modified API endpoints

**`GET /api/games`** — returns recent games for the authenticated user (used by Home and Profile pages)
```
Response: { games: [{ code, name, status, host_id, started_at, finished_at }] }
```

**`POST /api/games/:code/clone`** — clones a finished game for "Play Again"
```
Response: { code: <new_game_code> }
```
Calls existing `Game.clone_game/2` internally.

### Modified: lib/moth_web/controllers/page_controller.ex
```elixir
def spa(conn, _params) do
  conn
  |> put_resp_content_type("text/html")
  |> send_file(200, "priv/static/index.html")
end
```

### Modified: lib/moth_web/endpoint.ex — static paths
Update `MothWeb.static_paths/0` in `lib/moth_web.ex` to include Vite output:
```elixir
def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)
# Add: Vite outputs to priv/static/assets/ which is already covered.
# Ensure Plug.Static serves from priv/static with at: "/" for index.html.
```

### Modified: config/dev.exs — Vite watcher
Replace esbuild watcher:
```elixir
watchers: [
  node: [
    "node_modules/.bin/vite",
    "--config", "assets/vite.config.ts",
    cd: Path.expand("..", __DIR__)
  ]
]
```

### Modified: tailwind.config.js — content paths
Must be updated to scan `.vue` and `.ts` files instead of `.heex` and `.ex`:
```javascript
content: [
  './assets/js/**/*.{vue,ts,js}',
  './assets/index.html',
],
```
Without this, all Tailwind utility classes used only in Vue templates are purged in production builds.

### Modified: assets/package.json (NEW FILE)
The current setup resolves `phoenix` and `phoenix_live_view` from `../deps` via esbuild's `NODE_PATH`. Vite requires an actual `package.json` with npm dependencies:
```json
{
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build"
  },
  "dependencies": {
    "phoenix": "file:../deps/phoenix",
    "pinia": "^2.x",
    "vue": "^3.x",
    "vue-router": "^4.x"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.x",
    "@vue/test-utils": "^2.x",
    "typescript": "^5.x",
    "vite": "^5.x",
    "vitest": "^1.x"
  }
}
```
Note: `phoenix` is resolved from local `deps/` to stay in sync with the backend version.

### Modified: mix.exs
Remove `:esbuild` from `aliases` and `deps`. The Vite watcher replaces it.

## Component Mapping

| Current (HEEX/Hook) | Vue equivalent |
|---|---|
| `ui.ex` button | `components/ui/Button.vue` |
| `ui.ex` card | `components/ui/Card.vue` |
| `ui.ex` avatar | `components/ui/Avatar.vue` |
| `ui.ex` badge | `components/ui/Badge.vue` |
| `ui.ex` modal | `components/ui/Modal.vue` |
| `ui.ex` input_field | `components/ui/InputField.vue` |
| `ui.ex` toast | `components/ui/Toast.vue` |
| `ui.ex` segmented_control | `components/ui/SegmentedControl.vue` |
| `ui.ex` bottom_sheet | `components/ui/BottomSheet.vue` (touch drag-to-dismiss) |
| `ui.ex` connection_status | `components/ui/ConnectionStatus.vue` |
| `game.ex` ticket_grid | `components/game/TicketGrid.vue` |
| `game.ex` board | `components/game/Board.vue` |
| `game.ex` countdown_ring | `components/game/CountdownRing.vue` |
| `activity_feed.ex` (LiveComponent) | `components/game/ActivityFeed.vue` |
| JS hook: ThemeToggle | `themeStore` |
| JS hook: Countdown | `useCountdown.ts` composable |
| JS hook: Confetti | `useConfetti.ts` composable |
| JS hook: Presence | `presenceStore` + Channel |
| JS hook: CopyCode | inline Vue handler |
| JS hook: AutoDismiss | `Toast.vue` internal timer |
| JS hook: AutoScroll | `useAutoScroll.ts` composable |
| JS hook: FloatingReaction | `ReactionOverlay.vue` component |
| JS hook: TicketStrike | `TicketGrid.vue` — optimistic strike with in-flight dedup + reject animation |
| JS hook: BoardSheet | `BottomSheet.vue` + touch drag gesture |

### TicketStrike behaviour (important)
The current `ticket_strike.js` hook implements: optimistic local strike on click, dedup of in-flight strikes for the same number, and a shake animation on server rejection. `TicketGrid.vue` must replicate this: emit a `strike` event that `GamePlay.vue` sends over the channel, track in-flight numbers in local component state, apply `:class="{ rejected: strikeRejected }"` with CSS animation on the `StrikeResultEvent` rejection response.

## What Gets Removed

- `lib/moth_web/live/` — all LiveView modules
- `lib/moth_web/components/ui.ex` — HEEX component macros
- `lib/moth_web/components/game.ex` — HEEX game components
- `lib/moth_web/components/layouts/` — HEEX layouts (replaced by `index.html` + Vue layouts)
- `assets/js/hooks/` — all JS hooks (replaced by Vue composables/components)
- `assets/js/app.js` — replaced by `app.ts`
- `:esbuild` from `mix.exs`

## What Stays Unchanged

- All Elixir game engine logic (`lib/moth/game/server.ex`, `lib/moth/game/board.ex`, etc.)
- All existing `/api/*` REST endpoints and controllers (except OAuth callback)
- All database schemas and migrations
- `assets/css/app.css` — CSS variables and Tailwind theme
- The `phoenix.js` client library (resolved from `deps/phoenix` via package.json)

## Testing Strategy

### Backend (extend existing ExUnit suite)

**`test/moth_web/channels/game_channel_test.exs`** (new):
- Join with valid token → receives `GameJoinReply` with correct shape
- Join with invalid/expired token → connection rejected
- `"strike"` → `StrikeResultEvent` returned to socket
- `"claim"` valid → `PrizeClaimedEvent` broadcast to all
- `"claim"` bogey → `ClaimRejectionEvent` pushed to claimant only
- `"claim"` already claimed → `ClaimRejectionEvent` with `reason: "already_claimed"`
- `"chat"` → `ChatEvent` broadcast to all
- `"reaction"` → `ReactionEvent` broadcast to all
- Presence diff on join/leave → all subscribers receive `PresenceDiff`

**`test/moth_web/controllers/auth_controller_test.exs`** (update):
- OAuth callback redirects to `/#/auth/callback?token=…` not `/`

### Frontend (Vitest + Vue Test Utils)

**`gameStore.test.ts`**:
- `onPick` appends number, updates count
- `onPick` triggers auto-strike for numbers on `myTicket`
- `onStatusChange` transitions through valid states
- `onPrizeClaimed` marks prize claimed
- `claimPrize` sends channel message; `onBogey` updates player bogey count

**`useChannel.test.ts`** (uses injectable mock socket):
- Socket connects with `{ token }` in params
- Inbound events route to correct store handlers
- On disconnect, `channelConnected = false`
- On reconnect, `gameStore.join()` re-fetches full state

**`TicketGrid.test.ts`**:
- Renders 15 numbers in 3×9 grid
- Click triggers strike emit
- In-flight dedup prevents double-strike
- Shake animation applied on `StrikeResultEvent` rejection

### End-to-End (Playwright)

**Happy path:**
1. Auth via magic link
2. Create game, join as second player
3. Start game; verify number picks propagate to both clients
4. Strike a number; verify optimistic UI + server confirmation
5. Claim a prize when eligible; verify winner shown on both clients
6. End game; verify game-over screen
7. Play Again; verify redirect to new game

**Error paths:**
- Claim with no ticket match → bogey toast shown
- Channel disconnect mid-game → reconnecting indicator, state restored on reconnect
- Hard refresh on `/game/:code` → page loads correctly
- Navigate to `/game/:code/host` as non-host → redirected to player view

## Success Criteria

1. All 6 pages render all their states correctly (lobby, running, paused, finished, game-over)
2. Real-time game play works end-to-end for all channel event types (pick, strike, claim, chat, reaction, presence)
3. Theme toggle persists across page reloads
4. Auth flow works: magic link login, OAuth login, token stored and sent on all requests, token expiry redirects to `/auth`
5. Host-only actions work: start, pause, resume, end, play again
6. Prize claim rejection (bogey, already claimed) surfaces to claimant correctly
7. Activity feed receives and displays all 5 entry types (pick, chat, prize, bogey, system)
8. No HEEX or LiveView code remains
9. `npm run build` produces working static assets in `priv/static/` with no purged Tailwind classes
10. Deep-linking to any route works on hard browser refresh

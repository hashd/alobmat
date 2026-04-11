# Vue SPA Migration Design

**Date:** 2026-04-11
**Status:** Approved
**Author:** Kiran Danduprolu

## Background

The current Moth app uses Phoenix LiveView for server-side rendering. This has caused significant developer experience friction and bugs when using AI tooling to implement UI changes — HEEX templates and LiveView's state model are not well-supported by AI coding tools. The decision was made to replace the entire frontend with a Vue 3 SPA.

## Goal

Replace all LiveView/HEEX frontend code with a Vue 3 + TypeScript + Pinia + Vite SPA, while keeping the Phoenix/Elixir backend (API, Channels, GenServer game engine) completely intact.

## Approach

**Full SPA migration** — all 6 LiveView routes are removed. Phoenix serves a single `index.html` via a catch-all route. Vue Router handles all client-side navigation. No gradual migration, no mixed HEEX/Vue coexistence.

Rationale: a partial migration still leaves HEEX in the codebase, which doesn't solve the DX problem. The app has only 6 pages and the backend API endpoints already exist, making a full migration feasible.

## Architecture

```
Browser (Vue SPA)
├── Vue Router       — client-side routing
├── Pinia Stores     — app state (auth, game, theme, presence)
├── Vue SFCs         — pages and components
└── useChannel       — Phoenix WebSocket via phoenix.js

        ↕ HTTP (fetch)        ↕ WebSocket
Phoenix (Elixir Backend — unchanged)
├── REST API (/api/*)         — auth, user, game CRUD
├── Phoenix Channels          — real-time game events
├── Game GenServer            — state machine (untouched)
└── Static serving            — priv/static (Vite output)
```

### Build pipeline

Vite replaces esbuild. Assets live in `assets/`, Vite builds to `priv/static/`. In development, Vite runs as a watcher via `config/dev.exs` with a proxy forwarding `/api` and `/socket` to Phoenix on port 4000.

### Real-time

Phoenix Channels are used for real-time (not polling). The `useChannel` composable wraps `phoenix.js` Socket + Channel, joins `game:<code>` on mount, routes incoming events to Pinia store actions, and leaves on unmount. This is the same transport LiveView was using internally.

## File Structure

```
assets/
├── index.html                ← Vite entry point
├── vite.config.ts
├── tsconfig.json
└── js/
    ├── app.ts                ← mounts Vue app
    ├── router.ts             ← Vue Router
    ├── types/
    │   ├── domain.ts         ← User, Player, GameSettings, GameStatus, Ticket, Theme
    │   └── channel.ts        ← NumberPickedEvent, PrizeClaimedEvent, ReactionEvent, PresenceDiff, GameStatusEvent
    ├── stores/
    │   ├── auth.ts           ← user, token, login/logout/updateProfile
    │   ├── game.ts           ← full game state, channel event handlers
    │   ├── theme.ts          ← light/dark/system, localStorage persistence
    │   └── presence.ts       ← player presence map, syncPresence()
    ├── composables/
    │   ├── useChannel.ts     ← Phoenix Socket + Channel wrapper
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
        ├── ui/               ← Button, Card, Avatar, Badge, Modal, Toast, InputField, SegmentedControl, BottomSheet
        └── game/             ← TicketGrid, Board, CountdownRing, ReactionOverlay
```

All `.vue` files use `<script setup lang="ts">`.

## Pinia Stores

### authStore
- **State:** `user: User | null`, `token: string | null`
- **Actions:** `login()`, `logout()`, `refreshToken()`, `updateProfile()`
- **Persistence:** token stored in localStorage

### gameStore
- **State:**
  - `code: string`, `name: string`, `status: GameStatus`, `settings: GameSettings`
  - `board: { picks: number[]; numbers_picked_count: number }`
  - `myTicket: Ticket`, `myStruck: Set<number>`
  - `players: Player[]`
  - `prizes: Record<string, { status: 'unclaimed' | 'claimed'; winner_id?: string }>`
  - `reactions: Array<{ emoji: string; user_id: string; id: string }>`
  - `nextPickAt: string | null`, `channelConnected: boolean`
- **Actions:** `join()`, `strike(number)`, `claimPrize(prize: string)`
- **Channel handlers:** `onPick(NumberPickedEvent)`, `onPresence(PresenceDiff)`, `onReaction(ReactionEvent)`, `onStatusChange(GameStatusEvent)`, `onPrizeClaimed(PrizeClaimedEvent)`

### themeStore
- **State:** `theme: Theme`
- **Actions:** `toggle()`, `setTheme(theme)`
- **Side effect:** syncs `dark` class to `<html>`, persists to localStorage

### presenceStore
- **State:** `players: Map<string, { name: string, online: boolean }>`
- **Actions:** `syncPresence(diff: PresenceDiff)`

## TypeScript Types

### types/domain.ts
```typescript
interface User { id: string; name: string; email: string; avatar_url: string | null }
interface Player { user_id: string; name: string; prizes_won: string[]; bogeys: number }
interface GameSettings { interval: number; bogey_limit: number; enabled_prizes: string[] }
type GameStatus = 'lobby' | 'running' | 'paused' | 'finished'
type Ticket = (number | null)[][]
type Theme = 'light' | 'dark' | 'system'
```

### types/channel.ts
```typescript
interface NumberPickedEvent { number: number; picks: number[]; next_pick_at: string }
interface PrizeClaimedEvent { prize: string; winner_id: string; winner_name: string }
interface ReactionEvent { emoji: string; user_id: string }
interface GameStatusEvent { status: GameStatus }
interface PresenceMeta { name: string; online_at: string }
interface PresenceDiff { joins: Record<string, PresenceMeta>; leaves: Record<string, PresenceMeta> }
```

## Vue Router

```
/           → Home.vue
/auth       → Auth.vue        (magic link flow)
/profile    → Profile.vue     (requires auth)
/game/new   → NewGame.vue     (requires auth)
/game/:code → GamePlay.vue
/game/:code/host → HostDashboard.vue (requires auth + host)
```

Navigation guards enforce auth requirements using `authStore`.

## Authentication

The current app uses Phoenix cookie-based sessions (set server-side by LiveView). A Vue SPA cannot use these directly. Authentication must switch to **token-based** (JWT or Phoenix-signed tokens):

1. **Magic link flow:** User requests link via `/api/auth/magic` → clicks emailed link → `/api/auth/verify` returns a token → stored in `authStore` (localStorage) → sent as `Authorization: Bearer <token>` header on all API requests and as a connect param on the Phoenix Channel socket.
2. **OAuth (Google):** Redirect to `/auth/google` → Phoenix callback exchanges code → redirects to `/#/auth/callback?token=<token>` → Vue reads token from URL, stores in `authStore`.
3. **Token refresh:** `authStore.refreshToken()` calls `/api/auth/refresh` before expiry.
4. **Channel auth:** `useChannel` passes `{ token }` as connect params when opening the Phoenix Socket, which the channel's `connect/3` callback verifies.

The existing `/api/auth/*` endpoints already support token-based auth — no backend changes needed for this.

## Phoenix Changes

### router.ex
- Remove all `live` routes
- Keep all `/api/*` routes unchanged
- Add SPA catch-all: `get "/*path", PageController, :spa`

### page_controller.ex
```elixir
def spa(conn, _params) do
  conn
  |> put_resp_content_type("text/html")
  |> send_file(200, "priv/static/index.html")
end
```

### New: lib/moth_web/channels/game_channel.ex
Handles:
- `join "game:<code>"` — verifies auth token, loads game state, sends initial state to client
- Incoming: `"strike"`, `"claim"`, `"reaction"` messages from Vue client
- Outgoing: broadcasts `"number_picked"`, `"status_changed"`, `"prize_claimed"`, `"reaction"` to all subscribers

### config/dev.exs
Replace esbuild watcher with Vite:
```elixir
watchers: [
  node: ["node_modules/.bin/vite", "--config", "assets/vite.config.ts",
         cd: Path.expand("..", __DIR__)]
]
```

### mix.exs
Remove `:esbuild` dependency. Add `phoenix_js` to package.json (already present via phoenix.js in assets).

## What Gets Removed

- `lib/moth_web/live/` — all LiveView modules
- `lib/moth_web/components/ui.ex` — HEEX component macros
- `lib/moth_web/components/game.ex` — HEEX game components
- `lib/moth_web/components/layouts/` — HEEX layouts
- `assets/js/hooks/` — all JS hooks (replaced by Vue composables)
- `assets/js/app.js` — replaced by `app.ts`

## What Stays Unchanged

- All Elixir backend logic (game engine, auth, database schemas)
- All `/api/*` REST endpoints and controllers
- `assets/css/app.css` — CSS variables and Tailwind theme
- `tailwind.config.js`
- The `phoenix.js` client library (used by `useChannel.ts`)

## Component Mapping

| Current (HEEX) | Vue equivalent |
|---|---|
| `ui.ex` button | `components/ui/Button.vue` |
| `ui.ex` card | `components/ui/Card.vue` |
| `ui.ex` avatar | `components/ui/Avatar.vue` |
| `ui.ex` badge | `components/ui/Badge.vue` |
| `ui.ex` modal | `components/ui/Modal.vue` |
| `ui.ex` input_field | `components/ui/InputField.vue` |
| `ui.ex` toast | `components/ui/Toast.vue` |
| `ui.ex` segmented_control | `components/ui/SegmentedControl.vue` |
| `game.ex` ticket_grid | `components/game/TicketGrid.vue` |
| `game.ex` board | `components/game/Board.vue` |
| `game.ex` countdown_ring | `components/game/CountdownRing.vue` |
| JS hook: ThemeToggle | `themeStore` + `useTheme` |
| JS hook: Countdown | `useCountdown.ts` composable |
| JS hook: Confetti | `useConfetti.ts` composable |
| JS hook: Presence | `presenceStore` + Channel |
| JS hook: CopyCode | inline Vue handler |
| JS hook: AutoDismiss | `Toast.vue` internal timer |
| JS hook: AutoScroll | `useAutoScroll.ts` composable |
| JS hook: FloatingReaction | `ReactionOverlay.vue` component |

## Success Criteria

1. All 6 pages render correctly in Vue
2. Real-time game play works end-to-end (number picks propagate to all players)
3. Theme toggle persists across page reloads
4. Auth flow works (magic link + session)
5. No HEEX or LiveView code remains
6. Vite build produces working static assets in `priv/static/`

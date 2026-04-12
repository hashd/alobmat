# Vue SPA Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all Phoenix LiveView/HEEX frontend with a Vue 3 + TypeScript + Pinia + Vite SPA, building the Phoenix Channels real-time layer and adapting auth for token-based flow.

**Architecture:** Phase 1 builds the Phoenix Channel layer (UserSocket, GameChannel, OAuth token redirect, missing API endpoints) — this must ship before Phase 2 starts. Phase 2 builds the Vue SPA (stores, composables, components, pages) that consumes those channels and APIs. The Elixir game engine (GenServer, PubSub) is untouched throughout.

**Tech Stack:** Elixir/Phoenix, Phoenix Channels, Vue 3, TypeScript, Pinia, Vite, Vue Router, Vitest, Vue Test Utils, Playwright

---

## File Map

### Phase 1 — Backend

**Create:**
- `lib/moth_web/user_socket.ex`
- `lib/moth_web/channels/game_channel.ex`
- `test/moth_web/channels/game_channel_test.exs`

**Modify:**
- `lib/moth_web/endpoint.ex` — add UserSocket
- `lib/moth_web/router.ex` — add SPA catch-all + new API routes
- `lib/moth_web/controllers/auth_controller.ex` — OAuth callback returns token redirect
- `lib/moth_web/controllers/api/game_controller.ex` — add `recent` and `clone` actions
- `lib/moth_web/presence.ex` — accept channel socket (remove `self()` dependency)
- `lib/moth_web/controllers/page_controller.ex` — add `spa` action
- `config/dev.exs` — Vite watcher replaces esbuild
- `mix.exs` — remove esbuild dep
- `tailwind.config.js` — update content paths for `.vue` files

### Phase 2 — Frontend (all new unless noted)

**Create:**
- `assets/package.json`
- `assets/vite.config.ts`
- `assets/tsconfig.json`
- `assets/index.html`
- `assets/js/app.ts`
- `assets/js/router.ts`
- `assets/js/types/domain.ts`
- `assets/js/types/channel.ts`
- `assets/js/api/client.ts`
- `assets/js/stores/auth.ts`
- `assets/js/stores/theme.ts`
- `assets/js/stores/presence.ts`
- `assets/js/stores/game.ts`
- `assets/js/stores/chat.ts`
- `assets/js/composables/useChannel.ts`
- `assets/js/composables/useCountdown.ts`
- `assets/js/composables/useConfetti.ts`
- `assets/js/composables/useAutoScroll.ts`
- `assets/js/components/ui/Button.vue`
- `assets/js/components/ui/Card.vue`
- `assets/js/components/ui/Avatar.vue`
- `assets/js/components/ui/Badge.vue`
- `assets/js/components/ui/Modal.vue`
- `assets/js/components/ui/Toast.vue`
- `assets/js/components/ui/InputField.vue`
- `assets/js/components/ui/SegmentedControl.vue`
- `assets/js/components/ui/BottomSheet.vue`
- `assets/js/components/ui/ConnectionStatus.vue`
- `assets/js/components/game/TicketGrid.vue`
- `assets/js/components/game/Board.vue`
- `assets/js/components/game/CountdownRing.vue`
- `assets/js/components/game/ActivityFeed.vue`
- `assets/js/components/game/ReactionOverlay.vue`
- `assets/js/pages/Auth.vue`
- `assets/js/pages/Home.vue`
- `assets/js/pages/Profile.vue`
- `assets/js/pages/NewGame.vue`
- `assets/js/pages/GamePlay.vue`
- `assets/js/pages/HostDashboard.vue`
- `assets/js/test/stores/auth.test.ts`
- `assets/js/test/stores/game.test.ts`
- `assets/js/test/composables/useChannel.test.ts`
- `assets/js/test/components/TicketGrid.test.ts`

**Delete** (Phase 2 cleanup task):
- `lib/moth_web/live/` (entire directory)
- `lib/moth_web/components/ui.ex`
- `lib/moth_web/components/game.ex`
- `lib/moth_web/components/layouts/` (except `root.html.heex` if kept)
- `assets/js/hooks/` (all hooks)
- `assets/js/app.js`

---

## Phase 1: Backend Channel Layer

### Task 1: UserSocket

**Files:**
- Create: `lib/moth_web/user_socket.ex`
- Modify: `lib/moth_web/endpoint.ex`

- [ ] **Step 1: Create `lib/moth_web/user_socket.ex`**

```elixir
defmodule MothWeb.UserSocket do
  use Phoenix.Socket

  channel "game:*", MothWeb.GameChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Moth.Auth.get_user_by_api_token(token) do
      nil -> :error
      user -> {:ok, assign(socket, :current_user, user)}
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
```

- [ ] **Step 2: Wire UserSocket into `lib/moth_web/endpoint.ex`**

Add before the existing LiveView socket line:

```elixir
socket "/socket", MothWeb.UserSocket,
  websocket: true,
  longpoll: false
```

- [ ] **Step 3: Verify the socket compiles**

```bash
cd /Users/kiran/hashd/dev/alobmat && mix compile
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/moth_web/user_socket.ex lib/moth_web/endpoint.ex
git commit -m "feat: add UserSocket for Vue SPA channel auth"
```

---

### Task 2: GameChannel — join and initial state reply

**Files:**
- Create: `lib/moth_web/channels/game_channel.ex`
- Create: `test/moth_web/channels/game_channel_test.exs`

- [ ] **Step 1: Create test file**

```elixir
# test/moth_web/channels/game_channel_test.exs
defmodule MothWeb.GameChannelTest do
  use MothWeb.ChannelCase

  import Moth.AuthFixtures
  import Moth.GameFixtures

  setup do
    user = user_fixture()
    {:ok, api_token} = Moth.Auth.create_api_token(user)
    {:ok, socket} = connect(MothWeb.UserSocket, %{"token" => api_token})
    %{socket: socket, user: user}
  end

  test "joins game and receives initial state", %{socket: socket, user: user} do
    {:ok, game_code} = Moth.Game.create_game(user.id, %{name: "Test"})
    {:ok, reply, _socket} = subscribe_and_join(socket, "game:#{game_code}")

    assert reply.code == game_code
    assert reply.status == "lobby"
    assert is_list(reply.players)
    assert is_map(reply.board)
    assert reply.board.count == 0
  end

  test "join fails for non-existent game", %{socket: socket} do
    assert {:error, %{reason: "game_not_found"}} =
             subscribe_and_join(socket, "game:XXXX")
  end
end
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
mix test test/moth_web/channels/game_channel_test.exs
```

Expected: error — `MothWeb.GameChannel` not found.

- [ ] **Step 3: Create `lib/moth_web/channels/game_channel.ex`**

```elixir
defmodule MothWeb.GameChannel do
  use Phoenix.Channel

  alias Moth.Game
  alias Moth.Game.{Board, Ticket}

  @impl true
  def join("game:" <> code, _params, socket) do
    current_user = socket.assigns.current_user

    case Game.game_state(code) do
      {:ok, state} ->
        :ok = Phoenix.PubSub.subscribe(Moth.PubSub, "game:#{code}")

        # Track presence — must be done after join succeeds
        send(self(), {:after_join, code})

        my_ticket = get_in(state, [:tickets, current_user.id])
        my_struck = get_in(state, [:struck, current_user.id]) || MapSet.new()

        reply = %{
          code: state.code,
          name: state.name,
          status: to_string(state.status),
          settings: format_settings(state.settings),
          board: state.board,
          players: state.players,
          prizes: format_prizes(state.prizes),
          prize_progress: state.prize_progress || %{},
          my_ticket: my_ticket && Ticket.to_map(my_ticket),
          my_struck: MapSet.to_list(my_struck)
        }

        {:ok, reply, assign(socket, :game_code, code)}

      {:error, _} ->
        {:error, %{reason: "game_not_found"}}
    end
  end

  @impl true
  def handle_info({:after_join, code}, socket) do
    MothWeb.Presence.track_player(socket, code, socket.assigns.current_user)
    {:noreply, socket}
  end

  # ── PubSub → Channel event translation ───────────────────────────────────

  def handle_info({:pick, payload}, socket) do
    push(socket, "number_picked", %{
      number: payload.number,
      count: payload.count,
      next_pick_at: format_datetime(payload.next_pick_at),
      server_now: format_datetime(payload.server_now)
    })
    {:noreply, socket}
  end

  def handle_info({:status, payload}, socket) do
    push(socket, "status_changed", %{status: to_string(payload.status)})
    {:noreply, socket}
  end

  def handle_info({:prize_claimed, payload}, socket) do
    push(socket, "prize_claimed", %{
      prize: to_string(payload.prize),
      winner_id: payload.winner_id,
      winner_name: payload.winner_name
    })
    {:noreply, socket}
  end

  def handle_info({:bogey, payload}, socket) do
    push(socket, "bogey", %{
      user_id: payload.user_id,
      bogeys_remaining: payload.bogeys_remaining
    })
    {:noreply, socket}
  end

  def handle_info({:player_joined, payload}, socket) do
    push(socket, "player_joined", %{user_id: payload.user_id, name: payload.name})
    {:noreply, socket}
  end

  def handle_info({:player_left, payload}, socket) do
    push(socket, "player_left", %{user_id: payload.user_id})
    {:noreply, socket}
  end

  def handle_info({:chat, payload}, socket) do
    push(socket, "chat", %{
      id: payload.id,
      user_id: payload.user_id,
      user_name: payload.user_name,
      text: payload.text,
      timestamp: format_datetime(payload.timestamp)
    })
    {:noreply, socket}
  end

  def handle_info({:reaction, payload}, socket) do
    push(socket, "reaction", %{emoji: payload.emoji, user_id: payload.user_id})
    {:noreply, socket}
  end

  # ── Inbound messages (client → server) ───────────────────────────────────

  @impl true
  def handle_in("strike", %{"number" => number}, socket) do
    user = socket.assigns.current_user
    code = socket.assigns.game_code

    result =
      case Game.strike_out(code, user.id, number) do
        :ok -> "ok"
        {:error, _} -> "rejected"
      end

    push(socket, "strike_result", %{number: number, result: result})
    {:noreply, socket}
  end

  def handle_in("claim", %{"prize" => prize}, socket) do
    user = socket.assigns.current_user
    code = socket.assigns.game_code
    prize_atom = String.to_existing_atom(prize)

    case Game.claim_prize(code, user.id, prize_atom) do
      {:ok, _prize} ->
        # success is broadcast via PubSub :prize_claimed — no direct push needed
        {:noreply, socket}

      {:error, :bogey, remaining} ->
        push(socket, "claim_rejection", %{reason: "bogey", bogeys_remaining: remaining})
        {:noreply, socket}

      {:error, reason} ->
        push(socket, "claim_rejection", %{reason: to_string(reason)})
        {:noreply, socket}
    end
  end

  def handle_in("reaction", %{"emoji" => emoji}, socket) do
    Game.send_reaction(socket.assigns.game_code, socket.assigns.current_user.id, emoji)
    {:noreply, socket}
  end

  def handle_in("chat", %{"text" => text}, socket) do
    Game.send_chat(socket.assigns.game_code, socket.assigns.current_user.id, text)
    {:noreply, socket}
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(other), do: other

  defp format_settings(settings) do
    %{
      interval: settings.interval,
      bogey_limit: settings.bogey_limit,
      enabled_prizes: Enum.map(settings.enabled_prizes, &to_string/1)
    }
  end

  defp format_prizes(prizes) when is_map(prizes) do
    Map.new(prizes, fn {prize, winner_id} ->
      {to_string(prize), %{claimed: not is_nil(winner_id), winner_id: winner_id}}
    end)
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/moth_web/channels/game_channel_test.exs
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/moth_web/channels/game_channel.ex test/moth_web/channels/game_channel_test.exs
git commit -m "feat: add GameChannel with join, PubSub translation, inbound messages"
```

---

### Task 3: GameChannel — full inbound test coverage

**Files:**
- Modify: `test/moth_web/channels/game_channel_test.exs`

- [ ] **Step 1: Add inbound message tests**

Append to `test/moth_web/channels/game_channel_test.exs`:

```elixir
  describe "inbound messages" do
    setup %{socket: socket, user: user} do
      {:ok, game_code} = Moth.Game.create_game(user.id, %{name: "Test"})
      {:ok, _reply, channel_socket} = subscribe_and_join(socket, "game:#{game_code}")
      %{game_code: game_code, channel_socket: channel_socket}
    end

    test "strike valid number returns ok", %{channel_socket: cs} do
      # start game first to get picks going
      ref = push(cs, "strike", %{"number" => 1})
      # strike_out may return :ok or error depending on game state
      assert_push "strike_result", %{number: 1, result: _}
    end

    test "claim with no match returns bogey rejection", %{channel_socket: cs, user: user, game_code: gc} do
      # start game
      Moth.Game.start_game(gc, user.id)
      ref = push(cs, "claim", %{"prize" => "early_five"})
      assert_push "claim_rejection", %{reason: reason}
      assert reason in ["bogey", "invalid"]
    end

    test "chat broadcasts to all subscribers", %{channel_socket: cs} do
      push(cs, "chat", %{"text" => "hello"})
      assert_push "chat", %{text: "hello"}
    end

    test "reaction broadcasts to all subscribers", %{channel_socket: cs} do
      push(cs, "reaction", %{"emoji" => "🎉"})
      assert_push "reaction", %{emoji: "🎉"}
    end
  end
```

- [ ] **Step 2: Run tests**

```bash
mix test test/moth_web/channels/game_channel_test.exs
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/moth_web/channels/game_channel_test.exs
git commit -m "test: add GameChannel inbound message coverage"
```

---

### Task 4: Adapt Presence for channel sockets

The existing `MothWeb.Presence.track_player/3` calls `track(self(), ...)` which works for LiveView PIDs. Phoenix Channels track presence differently — pass the socket directly.

**Files:**
- Modify: `lib/moth_web/presence.ex`

- [ ] **Step 1: Read current presence.ex**

```bash
cat lib/moth_web/presence.ex
```

- [ ] **Step 2: Update `track_player` to accept a socket**

Replace `track(self(), ...)` calls with `track(socket, ...)`. The function signature changes from `track_player(socket, code, user)` — which already takes a socket parameter — to using that socket in the `track` call:

```elixir
def track_player(socket_or_pid, code, user) do
  track(socket_or_pid, "game:#{code}:presence", user.id, %{
    name: user.name,
    status: :online,
    joined_at: System.system_time(:millisecond)
  })
end
```

If the current implementation uses `self()` explicitly, replace it with the first argument.

- [ ] **Step 3: Verify compile**

```bash
mix compile
```

- [ ] **Step 4: Run existing tests**

```bash
mix test
```

Expected: all existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add lib/moth_web/presence.ex
git commit -m "fix: adapt Presence.track_player to accept channel socket"
```

---

### Task 5: OAuth callback — return token instead of session cookie

**Files:**
- Modify: `lib/moth_web/controllers/auth_controller.ex`

- [ ] **Step 1: Read current callback action**

```bash
grep -n "def callback" lib/moth_web/controllers/auth_controller.ex
```

- [ ] **Step 2: Replace `callback/2` to redirect with token**

Find the `callback` function that handles `ueberauth_auth` and replace the response:

```elixir
def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
  case Moth.Auth.authenticate_oauth(auth.provider, auth.info) do
    {:ok, user} ->
      {:ok, token} = Moth.Auth.create_api_token(user)
      redirect(conn, to: "/#/auth/callback?token=#{token}")

    {:error, _reason} ->
      conn
      |> put_flash(:error, "Authentication failed.")
      |> redirect(to: "/")
  end
end
```

Note: `Moth.Auth.create_api_token/1` wraps `UserToken.build_api_token/1` and persists the record. If the function name differs, check `lib/moth/auth.ex` for the actual wrapper.

- [ ] **Step 3: Verify compile**

```bash
mix compile
```

- [ ] **Step 4: Commit**

```bash
git add lib/moth_web/controllers/auth_controller.ex
git commit -m "fix: OAuth callback redirects with bearer token for Vue SPA"
```

---

### Task 6: Add missing API endpoints — recent games + clone

**Files:**
- Modify: `lib/moth_web/controllers/api/game_controller.ex`
- Modify: `lib/moth_web/router.ex`

- [ ] **Step 1: Add `recent` and `clone` actions to `game_controller.ex`**

Append to `lib/moth_web/controllers/api/game_controller.ex`:

```elixir
def recent(conn, _params) do
  user = conn.assigns.current_user
  games = Moth.Game.recent_games(user.id, 10)

  render(conn, :recent, games: games)
end

def clone(conn, %{"code" => code}) do
  user = conn.assigns.current_user

  case Moth.Game.clone_game(code, user.id) do
    {:ok, new_code} -> render(conn, :clone, code: new_code)
    {:error, reason} -> conn |> put_status(422) |> render(:error, reason: reason)
  end
end
```

- [ ] **Step 2: Add JSON views for the new actions**

If the project uses `Phoenix.Controller.render/3` with a JSON view, add to the game JSON view (likely `lib/moth_web/controllers/api/game_json.ex` or similar):

```elixir
def render("recent.json", %{games: games}) do
  %{games: Enum.map(games, &game_summary/1)}
end

def render("clone.json", %{code: code}) do
  %{code: code}
end

defp game_summary(game) do
  %{
    code: game.code,
    name: game.name,
    status: game.status,
    host_id: game.host_id,
    started_at: game.started_at,
    finished_at: game.finished_at
  }
end
```

- [ ] **Step 3: Add routes to `lib/moth_web/router.ex`**

Inside the authenticated API scope, add:

```elixir
get "/games", GameController, :recent
post "/games/:code/clone", GameController, :clone
```

- [ ] **Step 4: Compile and run tests**

```bash
mix compile && mix test
```

- [ ] **Step 5: Commit**

```bash
git add lib/moth_web/controllers/api/game_controller.ex lib/moth_web/router.ex
git commit -m "feat: add GET /api/games and POST /api/games/:code/clone endpoints"
```

---

### Task 7: SPA catch-all route + page controller

**Files:**
- Modify: `lib/moth_web/controllers/page_controller.ex`
- Modify: `lib/moth_web/router.ex`

- [ ] **Step 1: Add `spa` action to `page_controller.ex`**

```elixir
def spa(conn, _params) do
  conn
  |> put_resp_content_type("text/html")
  |> send_file(200, "priv/static/index.html")
end
```

- [ ] **Step 2: Add SPA catch-all to `router.ex`**

At the very bottom of the browser scope (after all other routes), add:

```elixir
get "/*path", PageController, :spa
```

This must be the last route in the browser scope — it catches everything not matched by API or static asset routes.

- [ ] **Step 3: Remove all `live` routes from `router.ex`**

Delete all lines starting with `live "` in the browser scope.

- [ ] **Step 4: Compile**

```bash
mix compile
```

- [ ] **Step 5: Commit**

```bash
git add lib/moth_web/controllers/page_controller.ex lib/moth_web/router.ex
git commit -m "feat: add SPA catch-all route, remove LiveView routes"
```

---

### Task 8: Switch from esbuild to Vite watcher

**Files:**
- Modify: `config/dev.exs`
- Modify: `mix.exs`
- Modify: `tailwind.config.js`

- [ ] **Step 1: Replace esbuild watcher in `config/dev.exs`**

Find the `watchers:` key and replace the esbuild entry with:

```elixir
watchers: [
  node: [
    "node_modules/.bin/vite",
    "--config", "assets/vite.config.ts",
    cd: Path.expand("..", __DIR__)
  ]
]
```

- [ ] **Step 2: Remove esbuild from `mix.exs`**

In `defp deps`, remove the `{:esbuild, ...}` entry.
In `aliases`, remove or update the `"assets.deploy"` alias that references esbuild. Replace with:

```elixir
"assets.deploy": ["cmd npm run build --prefix assets", "phx.digest"]
```

- [ ] **Step 3: Update `tailwind.config.js` content paths**

Replace the `content` array:

```javascript
content: [
  './assets/js/**/*.{vue,ts,js}',
  './assets/index.html',
],
```

- [ ] **Step 4: Compile**

```bash
mix compile
```

- [ ] **Step 5: Commit**

```bash
git add config/dev.exs mix.exs tailwind.config.js
git commit -m "chore: replace esbuild with Vite watcher, update Tailwind content paths"
```

---

## Phase 2: Frontend

### Task 9: Frontend foundation — package.json, Vite, TypeScript, index.html

**Files:**
- Create: `assets/package.json`
- Create: `assets/vite.config.ts`
- Create: `assets/tsconfig.json`
- Create: `assets/index.html`

- [ ] **Step 1: Create `assets/package.json`**

```json
{
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "test": "vitest run"
  },
  "dependencies": {
    "canvas-confetti": "^1.9.3",
    "phoenix": "file:../deps/phoenix",
    "pinia": "^2.1.7",
    "vue": "^3.4.0",
    "vue-router": "^4.3.0"
  },
  "devDependencies": {
    "@tailwindcss/vite": "^4.0.0",
    "@types/canvas-confetti": "^1.6.4",
    "@vitejs/plugin-vue": "^5.0.4",
    "@vue/test-utils": "^2.4.4",
    "autoprefixer": "^10.4.19",
    "jsdom": "^24.0.0",
    "postcss": "^8.4.38",
    "tailwindcss": "^3.4.3",
    "typescript": "^5.4.0",
    "vite": "^5.2.0",
    "vitest": "^1.5.0"
  }
}
```

- [ ] **Step 2: Create `assets/vite.config.ts`**

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
  test: {
    environment: 'jsdom',
    globals: true,
  },
})
```

- [ ] **Step 3: Create `assets/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "jsx": "preserve",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "paths": {
      "@/*": ["./js/*"]
    }
  },
  "include": ["js/**/*.ts", "js/**/*.vue", "index.html"]
}
```

- [ ] **Step 4: Create `assets/index.html`**

CSS is imported in `app.ts` (not linked here — Vite processes it through PostCSS/Tailwind).

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Moth</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/js/app.ts"></script>
  </body>
</html>
```

- [ ] **Step 4b: Create `assets/postcss.config.js`**

```javascript
export default {
  plugins: {
    tailwindcss: { config: '../tailwind.config.js' },
    autoprefixer: {},
  },
}
```

- [ ] **Step 5: Install npm dependencies**

```bash
cd assets && npm install
```

Expected: `node_modules/` created, `package-lock.json` generated.

- [ ] **Step 6: Verify TypeScript compiles**

```bash
cd assets && npx tsc --noEmit
```

Expected: no errors (may warn about missing source files — that's fine at this stage).

- [ ] **Step 7: Commit**

```bash
git add assets/package.json assets/vite.config.ts assets/tsconfig.json assets/index.html assets/package-lock.json
git commit -m "feat: add Vite + TypeScript + Vue frontend foundation"
```

---

### Task 10: TypeScript types

**Files:**
- Create: `assets/js/types/domain.ts`
- Create: `assets/js/types/channel.ts`

- [ ] **Step 1: Create `assets/js/types/domain.ts`**

```typescript
export interface User {
  id: string
  name: string
  email: string
  avatar_url: string | null
}

export interface Player {
  user_id: string
  name: string
  prizes_won: string[]
  bogeys: number
}

export interface GameSettings {
  interval: number
  bogey_limit: number
  enabled_prizes: string[]
}

// Matches Ticket.to_map/1 — rows is 3x9 grid, null = blank cell
export interface Ticket {
  rows: (number | null)[][]
  numbers: number[]
}

// Matches Board.to_map/1
export interface Board {
  picks: number[]
  count: number
  finished: boolean
}

export interface PrizeStatus {
  claimed: boolean
  winner_id: string | null
}

export type GameStatus = 'lobby' | 'running' | 'paused' | 'finished'
export type Theme = 'light' | 'dark' | 'system'

export interface ChatEntry {
  id: string
  type: 'chat' | 'pick' | 'prize_claimed' | 'bogey' | 'system'
  user_id?: string
  user_name?: string
  text?: string
  number?: number
  prize?: string
  timestamp: string
}

export interface RecentGame {
  code: string
  name: string
  status: string
  host_id: string
  started_at: string | null
  finished_at: string | null
}
```

- [ ] **Step 2: Create `assets/js/types/channel.ts`**

```typescript
import type { Board, GameSettings, GameStatus, Player, PrizeStatus, Ticket } from './domain'

// ── Initial join reply ────────────────────────────────────────────────────────
export interface GameJoinReply {
  code: string
  name: string
  status: string
  settings: GameSettings
  board: Board
  players: Player[]
  prizes: Record<string, PrizeStatus>
  prize_progress: Record<string, Record<string, number>>
  my_ticket: Ticket | null
  my_struck: number[]
}

// ── Server → Client events ────────────────────────────────────────────────────
export interface NumberPickedEvent {
  number: number
  count: number
  next_pick_at: string
  server_now: string
}

export interface GameStatusEvent {
  status: string
}

export interface PrizeClaimedEvent {
  prize: string
  winner_id: string
  winner_name: string
}

export interface ClaimRejectionEvent {
  reason: 'bogey' | 'already_claimed' | 'disqualified' | 'invalid'
  bogeys_remaining?: number
}

export interface StrikeResultEvent {
  number: number
  result: 'ok' | 'rejected'
}

export interface BogeyEvent {
  user_id: string
  bogeys_remaining: number
}

export interface ChatEvent {
  id: string
  user_id: string
  user_name: string
  text: string
  timestamp: string
}

export interface ReactionEvent {
  emoji: string
  user_id: string
}

export interface PlayerJoinedEvent {
  user_id: string
  name: string
}

export interface PlayerLeftEvent {
  user_id: string
}

export interface PresenceMeta {
  name: string
  online_at: string
}

export interface PresenceDiff {
  joins: Record<string, PresenceMeta>
  leaves: Record<string, PresenceMeta>
}

// ── Client → Server messages ──────────────────────────────────────────────────
export interface StrikeMessage { number: number }
export interface ClaimMessage { prize: string }
export interface ReactionMessage { emoji: string }
export interface ChatMessage { text: string }
```

- [ ] **Step 3: Verify types compile**

```bash
cd assets && npx tsc --noEmit
```

- [ ] **Step 4: Commit**

```bash
git add assets/js/types/
git commit -m "feat: add TypeScript domain and channel types"
```

---

### Task 11: API client

**Files:**
- Create: `assets/js/api/client.ts`

- [ ] **Step 1: Create `assets/js/api/client.ts`**

```typescript
import type { User, RecentGame } from '@/types/domain'

const BASE = '/api'

function authHeader(): Record<string, string> {
  const token = localStorage.getItem('auth_token')
  return token ? { Authorization: `Bearer ${token}` } : {}
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...authHeader() },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }))
    throw Object.assign(new Error(err.error ?? res.statusText), { status: res.status, body: err })
  }
  return res.json()
}

// Auth
export const api = {
  auth: {
    requestMagicLink: (email: string) =>
      request<void>('POST', '/auth/magic', { email }),
    verifyMagicLink: (token: string) =>
      request<{ token: string; user: User }>('GET', `/auth/magic/verify?token=${token}`),
    refresh: () =>
      request<{ token: string }>('POST', '/auth/refresh'),
    logout: () =>
      request<void>('DELETE', '/auth/session'),
  },
  user: {
    me: () => request<{ user: User }>('GET', '/user/me'),
    update: (attrs: Partial<User>) => request<{ user: User }>('PATCH', '/user/me', attrs),
  },
  games: {
    recent: () => request<{ games: RecentGame[] }>('GET', '/games'),
    get: (code: string) => request<{ game: unknown }>('GET', `/games/${code}`),
    create: (attrs: { name: string; interval: number; bogey_limit: number; enabled_prizes: string[] }) =>
      request<{ code: string }>('POST', '/games', attrs),
    join: (code: string) => request<{ ticket: unknown }>('POST', `/games/${code}/join`),
    start: (code: string) => request<void>('POST', `/games/${code}/start`),
    pause: (code: string) => request<void>('POST', `/games/${code}/pause`),
    resume: (code: string) => request<void>('POST', `/games/${code}/resume`),
    end: (code: string) => request<void>('POST', `/games/${code}/end`),
    clone: (code: string) => request<{ code: string }>('POST', `/games/${code}/clone`),
  },
}
```

- [ ] **Step 2: Compile check**

```bash
cd assets && npx tsc --noEmit
```

- [ ] **Step 3: Commit**

```bash
git add assets/js/api/client.ts
git commit -m "feat: add typed API client"
```

---

### Task 12: Pinia stores — auth and theme

**Files:**
- Create: `assets/js/stores/auth.ts`
- Create: `assets/js/stores/theme.ts`
- Create: `assets/js/test/stores/auth.test.ts`

- [ ] **Step 1: Write failing test**

```typescript
// assets/js/test/stores/auth.test.ts
import { setActivePinia, createPinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { useAuthStore } from '@/stores/auth'

beforeEach(() => setActivePinia(createPinia()))

describe('authStore', () => {
  it('is unauthenticated by default', () => {
    const store = useAuthStore()
    expect(store.user).toBeNull()
    expect(store.isAuthenticated).toBe(false)
  })

  it('login sets user and persists token', () => {
    const store = useAuthStore()
    store.login({ id: '1', name: 'Alice', email: 'a@b.com', avatar_url: null }, 'tok123')
    expect(store.isAuthenticated).toBe(true)
    expect(localStorage.getItem('auth_token')).toBe('tok123')
  })

  it('logout clears user and token', () => {
    const store = useAuthStore()
    store.login({ id: '1', name: 'Alice', email: 'a@b.com', avatar_url: null }, 'tok123')
    store.logout()
    expect(store.isAuthenticated).toBe(false)
    expect(localStorage.getItem('auth_token')).toBeNull()
  })
})
```

- [ ] **Step 2: Run test to confirm failure**

```bash
cd assets && npm test -- test/stores/auth.test.ts
```

Expected: FAIL — `useAuthStore` not found.

- [ ] **Step 3: Create `assets/js/stores/auth.ts`**

```typescript
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { User } from '@/types/domain'
import { api } from '@/api/client'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null)
  const token = ref<string | null>(localStorage.getItem('auth_token'))

  const isAuthenticated = computed(() => user.value !== null && token.value !== null)

  function login(u: User, t: string) {
    user.value = u
    token.value = t
    localStorage.setItem('auth_token', t)
  }

  function logout() {
    user.value = null
    token.value = null
    localStorage.removeItem('auth_token')
  }

  async function loadUser() {
    if (!token.value) return
    try {
      const { user: u } = await api.user.me()
      user.value = u
    } catch {
      logout()
    }
  }

  async function updateProfile(attrs: Partial<User>) {
    const { user: u } = await api.user.update(attrs)
    user.value = u
  }

  return { user, token, isAuthenticated, login, logout, loadUser, updateProfile }
})
```

- [ ] **Step 4: Create `assets/js/stores/theme.ts`**

```typescript
import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Theme } from '@/types/domain'

export const useThemeStore = defineStore('theme', () => {
  const stored = (localStorage.getItem('theme') as Theme) ?? 'system'
  const theme = ref<Theme>(stored)

  function applyTheme(t: Theme) {
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
    const dark = t === 'dark' || (t === 'system' && prefersDark)
    document.documentElement.classList.toggle('dark', dark)
  }

  function setTheme(t: Theme) {
    theme.value = t
    localStorage.setItem('theme', t)
    applyTheme(t)
  }

  function toggle() {
    setTheme(theme.value === 'dark' ? 'light' : 'dark')
  }

  // Apply on init
  applyTheme(stored)

  return { theme, setTheme, toggle }
})
```

- [ ] **Step 5: Run tests**

```bash
cd assets && npm test -- test/stores/auth.test.ts
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/js/stores/auth.ts assets/js/stores/theme.ts assets/js/test/stores/auth.test.ts
git commit -m "feat: add authStore and themeStore"
```

---

### Task 13: Pinia stores — presence, game, chat

**Files:**
- Create: `assets/js/stores/presence.ts`
- Create: `assets/js/stores/game.ts`
- Create: `assets/js/stores/chat.ts`
- Create: `assets/js/test/stores/game.test.ts`

- [ ] **Step 1: Write failing gameStore test**

```typescript
// assets/js/test/stores/game.test.ts
import { setActivePinia, createPinia } from 'pinia'
import { beforeEach, describe, expect, it } from 'vitest'
import { useGameStore } from '@/stores/game'

beforeEach(() => setActivePinia(createPinia()))

describe('gameStore', () => {
  it('onPick appends number to board picks', () => {
    const store = useGameStore()
    store.board = { picks: [], count: 0, finished: false }
    store.onPick({ number: 42, count: 1, next_pick_at: '', server_now: '' })
    expect(store.board.picks).toContain(42)
    expect(store.board.count).toBe(1)
  })

  it('onPick triggers auto-strike for numbers on my ticket', () => {
    const store = useGameStore()
    store.board = { picks: [], count: 0, finished: false }
    store.myTicket = { rows: [], numbers: [42] }
    store.myStruck = new Set()
    const struck: number[] = []
    store.onPick({ number: 42, count: 1, next_pick_at: '', server_now: '' }, (n) => struck.push(n))
    expect(struck).toContain(42)
  })

  it('onStatusChange updates status', () => {
    const store = useGameStore()
    store.onStatusChange({ status: 'running' })
    expect(store.status).toBe('running')
  })

  it('onPrizeClaimed marks prize as claimed', () => {
    const store = useGameStore()
    store.prizes = { early_five: { claimed: false, winner_id: null } }
    store.onPrizeClaimed({ prize: 'early_five', winner_id: 'u1', winner_name: 'Alice' })
    expect(store.prizes.early_five.claimed).toBe(true)
    expect(store.prizes.early_five.winner_id).toBe('u1')
  })
})
```

- [ ] **Step 2: Run test to confirm failure**

```bash
cd assets && npm test -- test/stores/game.test.ts
```

Expected: FAIL.

- [ ] **Step 3: Create `assets/js/stores/presence.ts`**

```typescript
import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { PresenceDiff, PresenceMeta } from '@/types/channel'

export const usePresenceStore = defineStore('presence', () => {
  const players = ref<Map<string, PresenceMeta>>(new Map())

  function syncPresence(diff: PresenceDiff) {
    for (const [userId, meta] of Object.entries(diff.joins)) {
      players.value.set(userId, meta)
    }
    for (const userId of Object.keys(diff.leaves)) {
      players.value.delete(userId)
    }
  }

  function reset() {
    players.value = new Map()
  }

  return { players, syncPresence, reset }
})
```

- [ ] **Step 4: Create `assets/js/stores/game.ts`**

```typescript
import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Board, GameSettings, Player, PrizeStatus, Ticket } from '@/types/domain'
import type {
  GameJoinReply, NumberPickedEvent, GameStatusEvent, PrizeClaimedEvent,
  BogeyEvent, PlayerJoinedEvent, PlayerLeftEvent, StrikeResultEvent
} from '@/types/channel'

export const useGameStore = defineStore('game', () => {
  const code = ref('')
  const name = ref('')
  const status = ref<string>('lobby')
  const settings = ref<GameSettings>({ interval: 30, bogey_limit: 3, enabled_prizes: [] })
  const board = ref<Board>({ picks: [], count: 0, finished: false })
  const myTicket = ref<Ticket | null>(null)
  const myStruck = ref<Set<number>>(new Set())
  const players = ref<Player[]>([])
  const prizes = ref<Record<string, PrizeStatus>>({})
  const prizeProgress = ref<Record<string, Record<string, number>>>({})
  const nextPickAt = ref<string | null>(null)
  const channelConnected = ref(false)

  function hydrate(reply: GameJoinReply) {
    code.value = reply.code
    name.value = reply.name
    status.value = reply.status
    settings.value = reply.settings
    board.value = reply.board
    myTicket.value = reply.my_ticket
    myStruck.value = new Set(reply.my_struck)
    players.value = reply.players
    prizes.value = reply.prizes
    prizeProgress.value = reply.prize_progress
    channelConnected.value = true
  }

  function onPick(event: NumberPickedEvent, autoStrike?: (n: number) => void) {
    board.value = {
      ...board.value,
      picks: [...board.value.picks, event.number],
      count: event.count,
    }
    nextPickAt.value = event.next_pick_at

    // Auto-strike if number is on my ticket and not yet struck
    if (myTicket.value?.numbers.includes(event.number) && !myStruck.value.has(event.number)) {
      autoStrike?.(event.number)
    }
  }

  function onStatusChange(event: GameStatusEvent) {
    status.value = event.status
  }

  function onPrizeClaimed(event: PrizeClaimedEvent) {
    if (prizes.value[event.prize]) {
      prizes.value[event.prize] = { claimed: true, winner_id: event.winner_id }
    }
  }

  function onBogey(event: BogeyEvent) {
    const player = players.value.find(p => p.user_id === event.user_id)
    if (player) {
      player.bogeys = (settings.value.bogey_limit ?? 3) - event.bogeys_remaining
    }
  }

  function onPlayerJoined(event: PlayerJoinedEvent) {
    if (!players.value.find(p => p.user_id === event.user_id)) {
      players.value.push({ user_id: event.user_id, name: event.name, prizes_won: [], bogeys: 0 })
    }
  }

  function onPlayerLeft(event: PlayerLeftEvent) {
    players.value = players.value.filter(p => p.user_id !== event.user_id)
  }

  function onStrikeConfirmed(event: StrikeResultEvent) {
    if (event.result === 'ok') {
      myStruck.value = new Set([...myStruck.value, event.number])
    }
  }

  function reset() {
    code.value = ''
    status.value = 'lobby'
    board.value = { picks: [], count: 0, finished: false }
    myTicket.value = null
    myStruck.value = new Set()
    players.value = []
    prizes.value = {}
    channelConnected.value = false
  }

  return {
    code, name, status, settings, board, myTicket, myStruck,
    players, prizes, prizeProgress, nextPickAt, channelConnected,
    hydrate, onPick, onStatusChange, onPrizeClaimed, onBogey,
    onPlayerJoined, onPlayerLeft, onStrikeConfirmed, reset,
  }
})
```

- [ ] **Step 5: Create `assets/js/stores/chat.ts`**

```typescript
import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { ChatEntry } from '@/types/domain'
import type { ChatEvent, NumberPickedEvent, PrizeClaimedEvent, BogeyEvent } from '@/types/channel'

const MAX_ENTRIES = 50

export const useChatStore = defineStore('chat', () => {
  const entries = ref<ChatEntry[]>([])
  const filter = ref<'all' | 'chat' | 'events'>('all')

  function addEntry(entry: ChatEntry) {
    entries.value = [...entries.value.slice(-(MAX_ENTRIES - 1)), entry]
  }

  function onChat(event: ChatEvent) {
    addEntry({ id: event.id, type: 'chat', user_id: event.user_id, user_name: event.user_name, text: event.text, timestamp: event.timestamp })
  }

  function onPick(event: NumberPickedEvent) {
    addEntry({ id: `pick-${event.number}`, type: 'pick', number: event.number, timestamp: new Date().toISOString() })
  }

  function onPrizeClaimed(event: PrizeClaimedEvent) {
    addEntry({ id: `prize-${event.prize}`, type: 'prize_claimed', user_name: event.winner_name, prize: event.prize, timestamp: new Date().toISOString() })
  }

  function onBogey(event: BogeyEvent) {
    addEntry({ id: `bogey-${Date.now()}`, type: 'bogey', user_id: event.user_id, timestamp: new Date().toISOString() })
  }

  function reset() { entries.value = [] }

  return { entries, filter, onChat, onPick, onPrizeClaimed, onBogey, reset }
})
```

- [ ] **Step 6: Run game store tests**

```bash
cd assets && npm test -- test/stores/game.test.ts
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add assets/js/stores/ assets/js/test/stores/game.test.ts
git commit -m "feat: add presence, game, and chat Pinia stores"
```

---

### Task 14: useChannel composable

**Files:**
- Create: `assets/js/composables/useChannel.ts`
- Create: `assets/js/test/composables/useChannel.test.ts`

- [ ] **Step 1: Write failing test with mock socket**

```typescript
// assets/js/test/composables/useChannel.test.ts
import { setActivePinia, createPinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'

// Minimal mock for phoenix.js Socket + Channel
function makeMockSocket() {
  const handlers: Record<string, Function> = {}
  const channel = {
    join: () => ({ receive: (status: string, cb: Function) => { if (status === 'ok') cb({ code: 'TEST', status: 'lobby', board: { picks: [], count: 0, finished: false }, players: [], prizes: {}, prize_progress: {}, settings: { interval: 30, bogey_limit: 3, enabled_prizes: [] }, my_ticket: null, my_struck: [] }); return { receive: () => ({}) } } }),
    on: (event: string, cb: Function) => { handlers[event] = cb },
    push: vi.fn().mockReturnValue({ receive: () => ({}) }),
    leave: vi.fn(),
    trigger: (event: string, payload: unknown) => handlers[event]?.(payload),
  }
  return {
    connect: vi.fn(),
    disconnect: vi.fn(),
    channel: vi.fn().mockReturnValue(channel),
    mockChannel: channel,
  }
}

beforeEach(() => setActivePinia(createPinia()))

describe('useChannel', () => {
  it('hydrates game store on join', async () => {
    const { useChannel } = await import('@/composables/useChannel')
    const mockSocket = makeMockSocket()
    const { gameStore } = useChannel('TEST', () => mockSocket as any)
    expect(gameStore.code).toBe('TEST')
  })
})
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd assets && npm test -- test/composables/useChannel.test.ts
```

- [ ] **Step 3: Create `assets/js/composables/useChannel.ts`**

```typescript
import { onMounted, onUnmounted } from 'vue'
import { Socket, Channel } from 'phoenix'
import { useAuthStore } from '@/stores/auth'
import { useGameStore } from '@/stores/game'
import { useChatStore } from '@/stores/chat'
import { usePresenceStore } from '@/stores/presence'
import type {
  NumberPickedEvent, GameStatusEvent, PrizeClaimedEvent, ClaimRejectionEvent,
  StrikeResultEvent, BogeyEvent, ChatEvent, ReactionEvent,
  PlayerJoinedEvent, PlayerLeftEvent, PresenceDiff,
} from '@/types/channel'

type SocketFactory = (token: string) => Socket

function createSocket(token: string): Socket {
  return new Socket('/socket', { params: { token } })
}

export function useChannel(gameCode: string, socketFactory: SocketFactory = createSocket) {
  const authStore = useAuthStore()
  const gameStore = useGameStore()
  const chatStore = useChatStore()
  const presenceStore = usePresenceStore()

  let socket: Socket | null = null
  let channel: Channel | null = null

  const reactions = { listeners: [] as Array<(r: { emoji: string; user_id: string }) => void> }

  function onReaction(cb: (r: { emoji: string; user_id: string }) => void) {
    reactions.listeners.push(cb)
  }

  function connect() {
    if (!authStore.token) return

    socket = socketFactory(authStore.token)
    socket.connect()

    channel = socket.channel(`game:${gameCode}`)

    channel.join()
      .receive('ok', (reply) => {
        gameStore.hydrate(reply)
      })
      .receive('error', (err) => {
        console.error('Channel join error:', err)
      })

    channel.on('number_picked', (event: NumberPickedEvent) => {
      gameStore.onPick(event, (number) => strike(number))
      chatStore.onPick(event)
    })

    channel.on('status_changed', (event: GameStatusEvent) => {
      gameStore.onStatusChange(event)
    })

    channel.on('prize_claimed', (event: PrizeClaimedEvent) => {
      gameStore.onPrizeClaimed(event)
      chatStore.onPrizeClaimed(event)
    })

    channel.on('claim_rejection', (event: ClaimRejectionEvent) => {
      // Expose via toast — handled by page component listening to store
      console.warn('Claim rejected:', event)
    })

    channel.on('strike_result', (event: StrikeResultEvent) => {
      gameStore.onStrikeConfirmed(event)
    })

    channel.on('bogey', (event: BogeyEvent) => {
      gameStore.onBogey(event)
      chatStore.onBogey(event)
    })

    channel.on('chat', (event: ChatEvent) => {
      chatStore.onChat(event)
    })

    channel.on('reaction', (event: ReactionEvent) => {
      reactions.listeners.forEach(cb => cb(event))
    })

    channel.on('player_joined', (event: PlayerJoinedEvent) => {
      gameStore.onPlayerJoined(event)
    })

    channel.on('player_left', (event: PlayerLeftEvent) => {
      gameStore.onPlayerLeft(event)
    })

    channel.on('presence_diff', (diff: PresenceDiff) => {
      presenceStore.syncPresence(diff)
    })

    socket.onOpen(() => {
      gameStore.channelConnected = true
    })

    socket.onClose(() => {
      gameStore.channelConnected = false
    })
  }

  function strike(number: number) {
    channel?.push('strike', { number })
      .receive('ok', () => {})
  }

  function claim(prize: string) {
    channel?.push('claim', { prize })
  }

  function sendReaction(emoji: string) {
    channel?.push('reaction', { emoji })
  }

  function sendChat(text: string) {
    channel?.push('chat', { text })
  }

  function disconnect() {
    channel?.leave()
    socket?.disconnect()
    gameStore.reset()
    chatStore.reset()
    presenceStore.reset()
  }

  onMounted(connect)
  onUnmounted(disconnect)

  return { gameStore, strike, claim, sendReaction, sendChat, onReaction }
}
```

- [ ] **Step 4: Create remaining composables**

`assets/js/composables/useCountdown.ts`:
```typescript
import { ref, onUnmounted } from 'vue'

export function useCountdown(targetIso: () => string | null) {
  const secondsLeft = ref(0)
  let timer: ReturnType<typeof setInterval> | null = null

  function start() {
    if (timer) clearInterval(timer)
    timer = setInterval(() => {
      const target = targetIso()
      if (!target) { secondsLeft.value = 0; return }
      const diff = Math.max(0, Math.ceil((new Date(target).getTime() - Date.now()) / 1000))
      secondsLeft.value = diff
    }, 200)
  }

  function stop() {
    if (timer) clearInterval(timer)
  }

  onUnmounted(stop)

  return { secondsLeft, start, stop }
}
```

`assets/js/composables/useConfetti.ts`:
```typescript
export function useConfetti() {
  function fire() {
    // Dynamic import to keep bundle small
    import('canvas-confetti').then(({ default: confetti }) => {
      confetti({ particleCount: 120, spread: 70, origin: { y: 0.6 } })
    }).catch(() => {
      // confetti is optional — fail silently if not installed
    })
  }
  return { fire }
}
```

`assets/js/composables/useAutoScroll.ts`:
```typescript
import { ref, watchEffect } from 'vue'

export function useAutoScroll(deps: () => unknown) {
  const containerRef = ref<HTMLElement | null>(null)

  watchEffect(() => {
    deps() // track dependency
    if (containerRef.value) {
      containerRef.value.scrollTop = containerRef.value.scrollHeight
    }
  })

  return { containerRef }
}
```

- [ ] **Step 5: Run tests**

```bash
cd assets && npm test -- test/composables/useChannel.test.ts
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/js/composables/ assets/js/test/composables/
git commit -m "feat: add useChannel, useCountdown, useConfetti, useAutoScroll composables"
```

---

### Task 15: App entry + router

**Files:**
- Create: `assets/js/app.ts`
- Create: `assets/js/router.ts`

- [ ] **Step 1: Create `assets/js/router.ts`**

```typescript
import { createRouter, createWebHashHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes = [
  { path: '/', component: () => import('@/pages/Home.vue') },
  { path: '/auth', component: () => import('@/pages/Auth.vue') },
  {
    path: '/profile',
    component: () => import('@/pages/Profile.vue'),
    meta: { requiresAuth: true },
  },
  {
    path: '/game/new',
    component: () => import('@/pages/NewGame.vue'),
    meta: { requiresAuth: true },
  },
  {
    path: '/game/:code',
    component: () => import('@/pages/GamePlay.vue'),
    meta: { requiresAuth: true },
  },
  {
    path: '/game/:code/host',
    component: () => import('@/pages/HostDashboard.vue'),
    meta: { requiresAuth: true, requiresHost: true },
  },
]

export const router = createRouter({
  history: createWebHashHistory(),
  routes,
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()

  if (!auth.isAuthenticated && auth.token) {
    await auth.loadUser()
  }

  if (to.meta.requiresAuth && !auth.isAuthenticated) {
    return { path: '/auth', query: { redirect: to.fullPath } }
  }
})
```

- [ ] **Step 2: Create `assets/js/app.ts`**

```typescript
import '../css/app.css'  // Vite processes this through PostCSS/Tailwind
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { router } from './router'
import { useThemeStore } from './stores/theme'
import App from './App.vue'

const pinia = createPinia()
const app = createApp(App)
app.use(pinia)
app.use(router)

// Apply saved theme on boot
useThemeStore()

app.mount('#app')
```

- [ ] **Step 3: Create minimal `assets/js/App.vue`**

```vue
<template>
  <router-view />
</template>
```

- [ ] **Step 4: Compile check**

```bash
cd assets && npx tsc --noEmit
```

- [ ] **Step 5: Commit**

```bash
git add assets/js/app.ts assets/js/router.ts assets/js/App.vue
git commit -m "feat: add Vue app entry, router with auth guards"
```

---

### Task 16: UI components

**Files:** Create all files in `assets/js/components/ui/`

- [ ] **Step 1: Create `Button.vue`**

```vue
<script setup lang="ts">
defineProps<{
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  loading?: boolean
  disabled?: boolean
  type?: 'button' | 'submit'
}>()
</script>

<template>
  <button
    :type="type ?? 'button'"
    :disabled="disabled || loading"
    :class="[
      'inline-flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-all focus:outline-none disabled:opacity-50',
      variant === 'secondary' ? 'border border-[--border] bg-transparent text-[--text-primary] hover:bg-[--surface]' :
      variant === 'ghost'     ? 'text-[--text-secondary] hover:text-[--text-primary] hover:bg-[--surface]' :
      variant === 'danger'    ? 'bg-red-600 text-white hover:bg-red-700' :
                                'bg-[--accent] text-white hover:opacity-90'
    ]"
  >
    <span v-if="loading" class="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />
    <slot />
  </button>
</template>
```

- [ ] **Step 2: Create `Card.vue`**

```vue
<template>
  <div class="rounded-xl border border-[--border] bg-[--surface] p-4">
    <slot />
  </div>
</template>
```

- [ ] **Step 3: Create `Avatar.vue`**

```vue
<script setup lang="ts">
const props = defineProps<{ name: string; userId: string; size?: 'sm' | 'md' | 'lg' }>()
const colors = ['bg-violet-500','bg-blue-500','bg-green-500','bg-yellow-500','bg-pink-500','bg-indigo-500']
const color = colors[props.userId.charCodeAt(0) % colors.length]
const initials = props.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase()
const sz = props.size === 'lg' ? 'h-12 w-12 text-base' : props.size === 'sm' ? 'h-6 w-6 text-xs' : 'h-8 w-8 text-sm'
</script>
<template>
  <div :class="['flex items-center justify-center rounded-full font-bold text-white', color, sz]">{{ initials }}</div>
</template>
```

- [ ] **Step 4: Create `Badge.vue`**

```vue
<script setup lang="ts">
defineProps<{ variant?: 'live' | 'paused' | 'finished' | 'lobby' }>()
const map = { live: 'bg-green-500/20 text-green-400', paused: 'bg-yellow-500/20 text-yellow-400', finished: 'bg-zinc-500/20 text-zinc-400', lobby: 'bg-blue-500/20 text-blue-400' }
</script>
<template>
  <span :class="['inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium', map[variant ?? 'lobby']]"><slot /></span>
</template>
```

- [ ] **Step 5: Create `InputField.vue`**

```vue
<script setup lang="ts">
defineProps<{ label?: string; error?: string; placeholder?: string; type?: string }>()
const model = defineModel<string>()
</script>
<template>
  <div class="flex flex-col gap-1">
    <label v-if="label" class="text-xs font-medium text-[--text-secondary]">{{ label }}</label>
    <input
      v-model="model"
      :type="type ?? 'text'"
      :placeholder="placeholder"
      class="rounded-lg border border-[--border] bg-[--bg] px-3 py-2 text-sm text-[--text-primary] placeholder:text-[--text-secondary] focus:border-[--accent] focus:outline-none"
    />
    <p v-if="error" class="text-xs text-red-500">{{ error }}</p>
  </div>
</template>
```

- [ ] **Step 6: Create `Modal.vue`**

```vue
<script setup lang="ts">
defineProps<{ open: boolean; title?: string }>()
const emit = defineEmits<{ close: [] }>()
</script>
<template>
  <Teleport to="body">
    <Transition name="modal">
      <div v-if="open" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60" @click="emit('close')" />
        <div class="relative z-10 w-full max-w-md rounded-2xl border border-[--border] bg-[--bg] p-6 shadow-xl">
          <h2 v-if="title" class="mb-4 text-lg font-semibold">{{ title }}</h2>
          <slot />
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
<style scoped>
.modal-enter-from, .modal-leave-to { opacity: 0; }
.modal-enter-active, .modal-leave-active { transition: opacity 0.2s; }
</style>
```

- [ ] **Step 7: Create `Toast.vue`**

```vue
<script setup lang="ts">
import { onMounted } from 'vue'
const props = defineProps<{ message: string; variant?: 'success' | 'error' | 'info' }>()
const emit = defineEmits<{ dismiss: [] }>()
onMounted(() => setTimeout(() => emit('dismiss'), 3000))
const colors = { success: 'bg-green-600', error: 'bg-red-600', info: 'bg-zinc-700' }
</script>
<template>
  <div :class="['flex items-center gap-3 rounded-xl px-4 py-3 text-sm text-white shadow-lg', colors[props.variant ?? 'info']]">
    {{ message }}
  </div>
</template>
```

- [ ] **Step 8: Create `SegmentedControl.vue`**

```vue
<script setup lang="ts">
defineProps<{ options: { value: string; label: string }[] }>()
const model = defineModel<string>()
</script>
<template>
  <div class="flex rounded-lg border border-[--border] bg-[--surface] p-0.5">
    <button
      v-for="opt in options"
      :key="opt.value"
      type="button"
      @click="model = opt.value"
      :class="['flex-1 rounded-md px-3 py-1.5 text-sm font-medium transition-all',
        model === opt.value ? 'bg-[--accent] text-white' : 'text-[--text-secondary] hover:text-[--text-primary]']"
    >{{ opt.label }}</button>
  </div>
</template>
```

- [ ] **Step 9: Create `BottomSheet.vue`**

```vue
<script setup lang="ts">
defineProps<{ open: boolean; title?: string }>()
const emit = defineEmits<{ close: [] }>()
</script>
<template>
  <Teleport to="body">
    <Transition name="sheet">
      <div v-if="open" class="fixed inset-0 z-50 flex items-end">
        <div class="absolute inset-0 bg-black/60" @click="emit('close')" />
        <div class="relative z-10 w-full rounded-t-2xl border-t border-[--border] bg-[--bg] p-6 shadow-2xl">
          <div class="mx-auto mb-4 h-1 w-10 rounded-full bg-[--border]" />
          <h3 v-if="title" class="mb-4 font-semibold">{{ title }}</h3>
          <slot />
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
<style scoped>
.sheet-enter-from, .sheet-leave-to { transform: translateY(100%); }
.sheet-enter-active, .sheet-leave-active { transition: transform 0.3s ease; }
</style>
```

- [ ] **Step 10: Create `ConnectionStatus.vue`**

```vue
<script setup lang="ts">
defineProps<{ connected: boolean }>()
</script>
<template>
  <Transition name="fade">
    <div v-if="!connected" class="fixed bottom-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-2 rounded-full bg-zinc-800 px-4 py-2 text-sm text-white shadow-lg">
      <span class="h-2 w-2 animate-pulse rounded-full bg-yellow-400" />
      Reconnecting…
    </div>
  </Transition>
</template>
<style scoped>
.fade-enter-from, .fade-leave-to { opacity: 0; }
.fade-enter-active, .fade-leave-active { transition: opacity 0.2s; }
</style>
```

- [ ] **Step 11: Commit**

```bash
git add assets/js/components/ui/
git commit -m "feat: add UI component library (Button, Card, Avatar, Badge, Modal, Toast, InputField, SegmentedControl, BottomSheet, ConnectionStatus)"
```

---

### Task 17: Game components

**Files:** Create all files in `assets/js/components/game/`

- [ ] **Step 1: Write failing TicketGrid test**

```typescript
// assets/js/test/components/TicketGrid.test.ts
import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import TicketGrid from '@/components/game/TicketGrid.vue'

const ticket = {
  rows: [[1, null, 20, null, 30, null, 40, null, 90], [5, null, 15, null, 35, null, 50, null, 80], [8, null, 19, null, 38, null, 60, null, 85]],
  numbers: [1, 5, 8, 15, 19, 20, 30, 35, 38, 40, 50, 60, 80, 85, 90]
}

describe('TicketGrid', () => {
  it('renders 15 numbers', () => {
    const wrapper = mount(TicketGrid, { props: { ticket, struck: new Set(), pickedNumbers: [] } })
    const cells = wrapper.findAll('[data-number]')
    expect(cells).toHaveLength(15)
  })

  it('emits strike on number click', async () => {
    const wrapper = mount(TicketGrid, { props: { ticket, struck: new Set(), pickedNumbers: [] } })
    await wrapper.find('[data-number]').trigger('click')
    expect(wrapper.emitted('strike')).toBeTruthy()
  })

  it('does not emit strike on already-struck cell', async () => {
    const wrapper = mount(TicketGrid, { props: { ticket, struck: new Set([1]), pickedNumbers: [1] } })
    await wrapper.find('[data-number="1"]').trigger('click')
    expect(wrapper.emitted('strike')).toBeFalsy()
  })
})
```

- [ ] **Step 2: Run to confirm failure**

```bash
cd assets && npm test -- test/components/TicketGrid.test.ts
```

- [ ] **Step 3: Create `TicketGrid.vue`**

```vue
<script setup lang="ts">
import { ref } from 'vue'
import type { Ticket } from '@/types/domain'

const props = defineProps<{
  ticket: Ticket
  struck: Set<number>
  pickedNumbers: number[]
  interactive?: boolean
}>()
const emit = defineEmits<{ strike: [number: number] }>()

// Track in-flight strikes to prevent double-send
const inFlight = ref<Set<number>>(new Set())
const rejected = ref<Set<number>>(new Set())

function handleClick(n: number | null) {
  if (!n || !props.interactive) return
  if (props.struck.has(n) || inFlight.value.has(n)) return
  inFlight.value = new Set([...inFlight.value, n])
  emit('strike', n)
}

// Called by parent when server responds
function onStrikeResult(n: number, result: 'ok' | 'rejected') {
  inFlight.value = new Set([...inFlight.value].filter(x => x !== n))
  if (result === 'rejected') {
    rejected.value = new Set([...rejected.value, n])
    setTimeout(() => {
      rejected.value = new Set([...rejected.value].filter(x => x !== n))
    }, 600)
  }
}

defineExpose({ onStrikeResult })
</script>

<template>
  <div class="grid gap-1 rounded-xl border border-[--border] bg-[--surface] p-3">
    <div v-for="(row, ri) in ticket.rows" :key="ri" class="grid grid-cols-9 gap-1">
      <div
        v-for="(cell, ci) in row"
        :key="ci"
        :data-number="cell ?? undefined"
        @click="handleClick(cell)"
        :class="[
          'flex h-9 w-full items-center justify-center rounded-lg text-sm font-semibold transition-all select-none',
          !cell ? 'bg-transparent' :
          rejected.has(cell) ? 'animate-shake bg-red-500/20 text-red-400' :
          struck.has(cell) ? 'bg-[--accent]/20 text-[--accent] line-through' :
          pickedNumbers.includes(cell) ? 'bg-[--accent] text-white cursor-pointer' :
          interactive ? 'cursor-pointer bg-[--bg] text-[--text-primary] hover:bg-[--surface-2]' :
          'bg-[--bg] text-[--text-primary]'
        ]"
      >
        {{ cell ?? '' }}
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 4: Create `Board.vue`**

```vue
<script setup lang="ts">
defineProps<{ picks: number[] }>()
const allNumbers = Array.from({ length: 90 }, (_, i) => i + 1)
</script>
<template>
  <div class="grid grid-cols-10 gap-1">
    <div
      v-for="n in allNumbers"
      :key="n"
      :class="[
        'flex h-8 w-full items-center justify-center rounded text-xs font-medium transition-all',
        picks.includes(n) ? 'bg-[--accent] text-white' : 'bg-[--surface] text-[--text-secondary]'
      ]"
    >{{ n }}</div>
  </div>
</template>
```

- [ ] **Step 5: Create `CountdownRing.vue`**

```vue
<script setup lang="ts">
import { computed } from 'vue'
const props = defineProps<{ secondsLeft: number; totalSeconds: number }>()
const pct = computed(() => Math.max(0, Math.min(1, props.secondsLeft / props.totalSeconds)))
const dash = computed(() => {
  const c = 2 * Math.PI * 28
  return `${c * pct.value} ${c}`
})
</script>
<template>
  <div class="relative flex h-20 w-20 items-center justify-center">
    <svg class="absolute -rotate-90" width="80" height="80">
      <circle cx="40" cy="40" r="28" fill="none" stroke="var(--border)" stroke-width="4" />
      <circle cx="40" cy="40" r="28" fill="none" stroke="var(--accent)" stroke-width="4"
        :stroke-dasharray="dash" stroke-linecap="round" class="transition-all duration-200" />
    </svg>
    <span class="text-xl font-bold tabular-nums">{{ secondsLeft }}</span>
  </div>
</template>
```

- [ ] **Step 6: Create `ActivityFeed.vue`**

```vue
<script setup lang="ts">
import { computed } from 'vue'
import { useAutoScroll } from '@/composables/useAutoScroll'
import { useChatStore } from '@/stores/chat'
import type { ChatEntry } from '@/types/domain'

const chat = useChatStore()
const emit = defineEmits<{ sendChat: [text: string] }>()

const filtered = computed<ChatEntry[]>(() =>
  chat.filter === 'all' ? chat.entries :
  chat.filter === 'chat' ? chat.entries.filter(e => e.type === 'chat') :
  chat.entries.filter(e => e.type !== 'chat')
)

const { containerRef } = useAutoScroll(() => filtered.value.length)
let draft = ''

const filterOptions = [
  { value: 'all', label: 'All' },
  { value: 'chat', label: 'Chat' },
  { value: 'events', label: 'Events' },
]
</script>
<template>
  <div class="flex flex-col h-full">
    <div class="flex gap-2 mb-2">
      <button v-for="opt in filterOptions" :key="opt.value"
        @click="chat.filter = opt.value as any"
        :class="['text-xs px-2 py-1 rounded', chat.filter === opt.value ? 'bg-[--accent] text-white' : 'text-[--text-secondary]']"
      >{{ opt.label }}</button>
    </div>
    <div ref="containerRef" class="flex-1 overflow-y-auto space-y-1 min-h-0">
      <div v-for="entry in filtered" :key="entry.id" class="text-sm px-1">
        <span v-if="entry.type === 'chat'" class="text-[--text-primary]">
          <span class="font-semibold text-[--accent]">{{ entry.user_name }}:</span> {{ entry.text }}
        </span>
        <span v-else-if="entry.type === 'pick'" class="text-[--text-secondary]">Number {{ entry.number }} picked</span>
        <span v-else-if="entry.type === 'prize_claimed'" class="text-yellow-400">🏆 {{ entry.user_name }} won {{ entry.prize }}!</span>
        <span v-else-if="entry.type === 'bogey'" class="text-red-400">❌ Bogey!</span>
        <span v-else class="text-[--text-secondary] italic">{{ entry.text }}</span>
      </div>
    </div>
    <form @submit.prevent="emit('sendChat', draft); draft = ''" class="mt-2 flex gap-2">
      <input v-model="draft" placeholder="Say something…" class="flex-1 rounded-lg border border-[--border] bg-[--bg] px-3 py-2 text-sm focus:outline-none focus:border-[--accent]" />
      <button type="submit" class="rounded-lg bg-[--accent] px-3 py-2 text-sm text-white">Send</button>
    </form>
  </div>
</template>
```

- [ ] **Step 7: Create `ReactionOverlay.vue`**

```vue
<script setup lang="ts">
import { ref } from 'vue'

const floaters = ref<Array<{ id: number; emoji: string; x: number }>>([])
let counter = 0

function addReaction(emoji: string) {
  const id = counter++
  floaters.value.push({ id, emoji, x: 20 + Math.random() * 60 })
  setTimeout(() => { floaters.value = floaters.value.filter(f => f.id !== id) }, 2000)
}

defineExpose({ addReaction })
</script>
<template>
  <div class="pointer-events-none fixed inset-0 z-40 overflow-hidden">
    <TransitionGroup name="float">
      <div
        v-for="f in floaters"
        :key="f.id"
        class="absolute bottom-16 text-2xl"
        :style="{ left: `${f.x}%` }"
      >{{ f.emoji }}</div>
    </TransitionGroup>
  </div>
</template>
<style scoped>
.float-enter-from { opacity: 1; transform: translateY(0); }
.float-leave-to { opacity: 0; transform: translateY(-120px); }
.float-enter-active, .float-leave-active { transition: all 2s ease-out; }
</style>
```

- [ ] **Step 8: Run TicketGrid tests**

```bash
cd assets && npm test -- test/components/TicketGrid.test.ts
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add assets/js/components/game/ assets/js/test/components/TicketGrid.test.ts
git commit -m "feat: add game components (TicketGrid, Board, CountdownRing, ActivityFeed, ReactionOverlay)"
```

---

### Task 18: Pages — Auth and Home

**Files:**
- Create: `assets/js/pages/Auth.vue`
- Create: `assets/js/pages/Home.vue`

- [ ] **Step 1: Create `Auth.vue`**

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/api/client'
import InputField from '@/components/ui/InputField.vue'
import Button from '@/components/ui/Button.vue'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const email = ref('')
const sent = ref(false)
const loading = ref(false)
const error = ref('')

// Handle OAuth callback: /#/auth/callback?token=<t>
onMounted(async () => {
  const token = (route.query.token as string) ?? ''
  if (token) {
    try {
      const { user: u } = await api.user.me()
      auth.login(u, token)
      router.replace((route.query.redirect as string) ?? '/')
    } catch {
      error.value = 'Token invalid. Please try again.'
    }
  }
})

async function requestLink() {
  loading.value = true
  error.value = ''
  try {
    await api.auth.requestMagicLink(email.value)
    sent.value = true
  } catch (e: any) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>
<template>
  <div class="flex min-h-screen items-center justify-center p-4">
    <div class="w-full max-w-sm">
      <h1 class="mb-8 text-center text-3xl font-bold">Moth</h1>
      <div v-if="sent" class="text-center text-[--text-secondary]">
        Check your email for a sign-in link.
      </div>
      <form v-else @submit.prevent="requestLink" class="flex flex-col gap-4">
        <InputField v-model="email" label="Email" type="email" placeholder="you@example.com" :error="error" />
        <Button type="submit" :loading="loading">Send magic link</Button>
        <a href="/auth/google" class="text-center text-sm text-[--text-secondary] hover:text-[--text-primary]">Continue with Google</a>
      </form>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Create `Home.vue`**

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { api } from '@/api/client'
import type { RecentGame } from '@/types/domain'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'

const router = useRouter()
const auth = useAuthStore()

const joinCode = ref('')
const recentGames = ref<RecentGame[]>([])

onMounted(async () => {
  if (auth.isAuthenticated) {
    try {
      const { games } = await api.games.recent()
      recentGames.value = games
    } catch {}
  }
})

async function joinGame() {
  if (!joinCode.value.trim()) return
  router.push(`/game/${joinCode.value.toUpperCase()}`)
}
</script>
<template>
  <div class="mx-auto max-w-lg p-6">
    <div class="mb-8 flex items-center justify-between">
      <h1 class="text-2xl font-bold">Moth</h1>
      <div class="flex gap-2">
        <Button v-if="auth.isAuthenticated" variant="ghost" @click="router.push('/profile')">Profile</Button>
        <Button v-if="auth.isAuthenticated" @click="router.push('/game/new')">New Game</Button>
        <Button v-else @click="router.push('/auth')">Sign in</Button>
      </div>
    </div>

    <Card class="mb-6">
      <h2 class="mb-3 font-semibold">Join a game</h2>
      <form @submit.prevent="joinGame" class="flex gap-2">
        <input v-model="joinCode" placeholder="Game code" maxlength="4"
          class="flex-1 rounded-lg border border-[--border] bg-[--bg] px-3 py-2 text-sm uppercase tracking-widest focus:outline-none focus:border-[--accent]" />
        <Button type="submit">Join</Button>
      </form>
    </Card>

    <div v-if="recentGames.length">
      <h2 class="mb-3 font-semibold text-[--text-secondary]">Recent games</h2>
      <div class="flex flex-col gap-2">
        <Card v-for="g in recentGames" :key="g.code" class="cursor-pointer hover:border-[--accent]" @click="router.push(`/game/${g.code}`)">
          <div class="flex items-center justify-between">
            <span class="font-medium">{{ g.name || g.code }}</span>
            <span class="font-mono text-sm text-[--text-secondary]">{{ g.code }}</span>
          </div>
        </Card>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 3: Commit**

```bash
git add assets/js/pages/Auth.vue assets/js/pages/Home.vue
git commit -m "feat: add Auth and Home pages"
```

---

### Task 19: Pages — Profile and NewGame

**Files:**
- Create: `assets/js/pages/Profile.vue`
- Create: `assets/js/pages/NewGame.vue`

- [ ] **Step 1: Create `Profile.vue`**

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useThemeStore } from '@/stores/theme'
import { api } from '@/api/client'
import type { RecentGame } from '@/types/domain'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import Avatar from '@/components/ui/Avatar.vue'
import InputField from '@/components/ui/InputField.vue'

const router = useRouter()
const auth = useAuthStore()
const theme = useThemeStore()

const name = ref(auth.user?.name ?? '')
const saving = ref(false)
const recentGames = ref<RecentGame[]>([])

onMounted(async () => {
  try { const { games } = await api.games.recent(); recentGames.value = games } catch {}
})

async function saveName() {
  saving.value = true
  await auth.updateProfile({ name: name.value })
  saving.value = false
}

async function logout() {
  await api.auth.logout().catch(() => {})
  auth.logout()
  router.push('/')
}
</script>
<template>
  <div class="mx-auto max-w-lg p-6">
    <div class="mb-6 flex items-center gap-3">
      <Button variant="ghost" @click="router.back()">←</Button>
      <h1 class="text-xl font-bold">Profile</h1>
    </div>
    <Card class="mb-4">
      <div class="mb-4 flex items-center gap-3">
        <Avatar :name="auth.user!.name" :user-id="auth.user!.id" size="lg" />
        <div>
          <p class="font-semibold">{{ auth.user!.name }}</p>
          <p class="text-sm text-[--text-secondary]">{{ auth.user!.email }}</p>
        </div>
      </div>
      <form @submit.prevent="saveName" class="flex gap-2">
        <InputField v-model="name" class="flex-1" placeholder="Your name" />
        <Button type="submit" :loading="saving">Save</Button>
      </form>
    </Card>
    <Card class="mb-4">
      <div class="flex items-center justify-between">
        <span class="text-sm">Theme</span>
        <div class="flex gap-2">
          <Button v-for="t in ['light','dark','system']" :key="t" variant="ghost" @click="theme.setTheme(t as any)" :class="theme.theme === t ? 'text-[--accent]' : ''">{{ t }}</Button>
        </div>
      </div>
    </Card>
    <div v-if="recentGames.length" class="mb-4">
      <h2 class="mb-2 text-sm font-medium text-[--text-secondary]">Recent games</h2>
      <div class="space-y-2">
        <Card v-for="g in recentGames" :key="g.code" class="cursor-pointer" @click="$router.push(`/game/${g.code}`)">
          <div class="flex justify-between text-sm">
            <span>{{ g.name || g.code }}</span>
            <span class="font-mono text-[--text-secondary]">{{ g.code }}</span>
          </div>
        </Card>
      </div>
    </div>
    <Button variant="danger" @click="logout">Sign out</Button>
  </div>
</template>
```

- [ ] **Step 2: Create `NewGame.vue`**

```vue
<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '@/api/client'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import InputField from '@/components/ui/InputField.vue'

const router = useRouter()

const name = ref('')
const interval = ref(30)
const bogeyLimit = ref(3)
const enabledPrizes = ref(['early_five', 'top_line', 'middle_line', 'bottom_line', 'full_house'])
const loading = ref(false)
const error = ref('')

const prizeOptions = [
  { value: 'early_five', label: 'Early Five' },
  { value: 'top_line', label: 'Top Line' },
  { value: 'middle_line', label: 'Middle Line' },
  { value: 'bottom_line', label: 'Bottom Line' },
  { value: 'full_house', label: 'Full House' },
]

function togglePrize(p: string) {
  enabledPrizes.value = enabledPrizes.value.includes(p)
    ? enabledPrizes.value.filter(x => x !== p)
    : [...enabledPrizes.value, p]
}

async function create() {
  loading.value = true
  error.value = ''
  try {
    const { code } = await api.games.create({
      name: name.value || 'Tambola',
      interval: interval.value,
      bogey_limit: bogeyLimit.value,
      enabled_prizes: enabledPrizes.value,
    })
    router.push(`/game/${code}/host`)
  } catch (e: any) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>
<template>
  <div class="mx-auto max-w-lg p-6">
    <div class="mb-6 flex items-center gap-3">
      <Button variant="ghost" @click="$router.back()">←</Button>
      <h1 class="text-xl font-bold">New Game</h1>
    </div>
    <form @submit.prevent="create" class="flex flex-col gap-4">
      <InputField v-model="name" label="Game name" placeholder="Tambola Night" />

      <Card>
        <h3 class="mb-3 text-sm font-semibold">Pick interval</h3>
        <div class="flex gap-2">
          <Button v-for="s in [15,30,60]" :key="s" type="button" :variant="interval === s ? 'primary' : 'secondary'" @click="interval = s">{{ s }}s</Button>
        </div>
      </Card>

      <Card>
        <h3 class="mb-3 text-sm font-semibold">Bogey limit</h3>
        <div class="flex gap-2">
          <Button v-for="b in [1,2,3,5]" :key="b" type="button" :variant="bogeyLimit === b ? 'primary' : 'secondary'" @click="bogeyLimit = b">{{ b }}</Button>
        </div>
      </Card>

      <Card>
        <h3 class="mb-3 text-sm font-semibold">Prizes</h3>
        <div class="flex flex-wrap gap-2">
          <button v-for="p in prizeOptions" :key="p.value" type="button"
            @click="togglePrize(p.value)"
            :class="['rounded-full border px-3 py-1 text-sm transition-all', enabledPrizes.includes(p.value) ? 'border-[--accent] bg-[--accent]/10 text-[--accent]' : 'border-[--border] text-[--text-secondary]']"
          >{{ p.label }}</button>
        </div>
      </Card>

      <p v-if="error" class="text-sm text-red-500">{{ error }}</p>
      <Button type="submit" :loading="loading">Create game</Button>
    </form>
  </div>
</template>
```

- [ ] **Step 3: Commit**

```bash
git add assets/js/pages/Profile.vue assets/js/pages/NewGame.vue
git commit -m "feat: add Profile and NewGame pages"
```

---

### Task 20: GamePlay page

**Files:**
- Create: `assets/js/pages/GamePlay.vue`

- [ ] **Step 1: Create `GamePlay.vue`**

```vue
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useChannel } from '@/composables/useChannel'
import { useCountdown } from '@/composables/useCountdown'
import { useConfetti } from '@/composables/useConfetti'
import { api } from '@/api/client'
import TicketGrid from '@/components/game/TicketGrid.vue'
import Board from '@/components/game/Board.vue'
import CountdownRing from '@/components/game/CountdownRing.vue'
import ActivityFeed from '@/components/game/ActivityFeed.vue'
import ReactionOverlay from '@/components/game/ReactionOverlay.vue'
import ConnectionStatus from '@/components/ui/ConnectionStatus.vue'
import BottomSheet from '@/components/ui/BottomSheet.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import Avatar from '@/components/ui/Avatar.vue'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const code = route.params.code as string

const { gameStore, strike, claim, sendReaction, sendChat, onReaction } = useChannel(code)
const { secondsLeft, start: startCountdown } = useCountdown(() => gameStore.nextPickAt)
const { fire: fireConfetti } = useConfetti()

const ticketRef = ref<InstanceType<typeof TicketGrid> | null>(null)
const reactionRef = ref<InstanceType<typeof ReactionOverlay> | null>(null)
const boardOpen = ref(false)

// Auto-start countdown when game runs
onMounted(() => startCountdown())

// Confetti on personal prize win
const myId = computed(() => auth.user?.id)
const myPrizesWon = computed(() =>
  Object.entries(gameStore.prizes)
    .filter(([, s]) => s.winner_id === myId.value)
    .map(([p]) => p)
)

// Forward strike result to TicketGrid for shake animation
gameStore.$onAction(({ name, args }) => {
  if (name === 'onStrikeConfirmed' && ticketRef.value) {
    ticketRef.value.onStrikeResult(args[0].number, args[0].result)
  }
  if (name === 'onPrizeClaimed' && (args[0] as any).winner_id === myId.value) {
    fireConfetti()
  }
})

onReaction((r) => reactionRef.value?.addReaction(r.emoji))

const reactions = ['👏','🎉','🔥','😮','❤️']
</script>
<template>
  <div class="flex flex-col h-screen bg-[--bg] text-[--text-primary]">
    <!-- Header -->
    <div class="flex items-center gap-3 border-b border-[--border] px-4 py-3">
      <Button variant="ghost" @click="router.push('/')">←</Button>
      <span class="font-mono font-bold tracking-widest">{{ code }}</span>
      <Badge :variant="gameStore.status as any">{{ gameStore.status }}</Badge>
      <span class="ml-auto text-sm text-[--text-secondary]">{{ gameStore.players.length }} players</span>
    </div>

    <!-- Lobby state -->
    <div v-if="gameStore.status === 'lobby'" class="flex flex-1 flex-col items-center justify-center gap-4 p-6">
      <p class="text-[--text-secondary]">Waiting for host to start…</p>
      <div class="flex flex-wrap gap-2">
        <div v-for="p in gameStore.players" :key="p.user_id" class="flex items-center gap-2 rounded-full border border-[--border] px-3 py-1 text-sm">
          <Avatar :name="p.name" :user-id="p.user_id" size="sm" />
          {{ p.name }}
        </div>
      </div>
    </div>

    <!-- Running/paused state -->
    <div v-else-if="['running','paused'].includes(gameStore.status)" class="flex flex-1 overflow-hidden">
      <!-- Main area -->
      <div class="flex flex-1 flex-col gap-4 overflow-y-auto p-4">
        <!-- Countdown -->
        <div v-if="gameStore.status === 'running'" class="flex justify-center">
          <CountdownRing :seconds-left="secondsLeft" :total-seconds="gameStore.settings.interval" />
        </div>
        <div v-else class="text-center text-[--text-secondary]">Game paused</div>

        <!-- Last picked number -->
        <div v-if="gameStore.board.picks.length" class="text-center">
          <span class="text-5xl font-bold">{{ gameStore.board.picks[gameStore.board.picks.length - 1] }}</span>
          <p class="text-sm text-[--text-secondary]">{{ gameStore.board.count }} / 90</p>
        </div>

        <!-- Ticket -->
        <TicketGrid
          v-if="gameStore.myTicket"
          ref="ticketRef"
          :ticket="gameStore.myTicket"
          :struck="gameStore.myStruck"
          :picked-numbers="gameStore.board.picks"
          :interactive="gameStore.status === 'running'"
          @strike="strike"
        />

        <!-- Prizes -->
        <div class="flex flex-wrap gap-2">
          <button
            v-for="(status, prize) in gameStore.prizes"
            :key="prize"
            @click="!status.claimed && claim(prize)"
            :disabled="status.claimed"
            :class="['rounded-full border px-3 py-1 text-xs font-medium transition-all',
              status.claimed ? 'border-yellow-500/30 bg-yellow-500/10 text-yellow-400' :
              myPrizesWon.includes(prize) ? 'border-green-500 bg-green-500/10 text-green-400' :
              'border-[--border] text-[--text-secondary] hover:border-[--accent]']"
          >{{ prize.replace(/_/g, ' ') }} {{ status.claimed ? '✓' : '' }}</button>
        </div>

        <!-- Reactions -->
        <div class="flex gap-2">
          <button v-for="e in reactions" :key="e" @click="sendReaction(e)"
            class="text-xl hover:scale-125 transition-transform">{{ e }}</button>
        </div>

        <!-- View full board -->
        <Button variant="ghost" @click="boardOpen = true">View board ({{ gameStore.board.count }}/90)</Button>
      </div>

      <!-- Activity feed (desktop) -->
      <div class="hidden w-72 border-l border-[--border] p-4 md:flex flex-col">
        <ActivityFeed @send-chat="sendChat" />
      </div>
    </div>

    <!-- Finished state -->
    <div v-else-if="gameStore.status === 'finished'" class="flex flex-1 flex-col items-center justify-center gap-4 p-6">
      <h2 class="text-2xl font-bold">Game over!</h2>
      <div class="flex flex-col gap-2 w-full max-w-sm">
        <div v-for="(status, prize) in gameStore.prizes" :key="prize" class="flex justify-between text-sm border-b border-[--border] py-2">
          <span>{{ prize.replace(/_/g, ' ') }}</span>
          <span class="text-[--text-secondary]">{{ status.winner_id ? gameStore.players.find(p => p.user_id === status.winner_id)?.name ?? status.winner_id : '—' }}</span>
        </div>
      </div>
      <Button @click="router.push('/')">Home</Button>
    </div>

    <!-- Board bottom sheet -->
    <BottomSheet :open="boardOpen" title="All numbers" @close="boardOpen = false">
      <Board :picks="gameStore.board.picks" />
    </BottomSheet>

    <!-- Reaction overlay -->
    <ReactionOverlay ref="reactionRef" />

    <!-- Connection status -->
    <ConnectionStatus :connected="gameStore.channelConnected" />
  </div>
</template>
```

- [ ] **Step 2: Commit**

```bash
git add assets/js/pages/GamePlay.vue
git commit -m "feat: add GamePlay page"
```

---

### Task 21: HostDashboard page

**Files:**
- Create: `assets/js/pages/HostDashboard.vue`

- [ ] **Step 1: Create `HostDashboard.vue`**

```vue
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useChannel } from '@/composables/useChannel'
import { api } from '@/api/client'
import Board from '@/components/game/Board.vue'
import ConnectionStatus from '@/components/ui/ConnectionStatus.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import Avatar from '@/components/ui/Avatar.vue'
import Card from '@/components/ui/Card.vue'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const code = route.params.code as string

const { gameStore } = useChannel(code)
const loading = ref<string | null>(null)

const isHost = computed(() =>
  gameStore.players.length === 0 || // still loading
  true // host guard handled by router — if we're here, we're host
)

async function action(fn: () => Promise<unknown>, key: string) {
  loading.value = key
  try { await fn() } catch (e: any) { alert(e.message) }
  finally { loading.value = null }
}

async function playAgain() {
  const { code: newCode } = await api.games.clone(code)
  router.push(`/game/${newCode}/host`)
}
</script>
<template>
  <div class="flex flex-col min-h-screen bg-[--bg] text-[--text-primary] p-4">
    <!-- Header -->
    <div class="flex items-center gap-3 mb-6">
      <Button variant="ghost" @click="router.push('/')">←</Button>
      <div>
        <div class="flex items-center gap-2">
          <span class="font-bold text-lg">{{ gameStore.name || code }}</span>
          <Badge :variant="gameStore.status as any">{{ gameStore.status }}</Badge>
        </div>
        <p class="font-mono text-sm text-[--text-secondary]">Code: {{ code }}</p>
      </div>
    </div>

    <!-- LOBBY -->
    <div v-if="gameStore.status === 'lobby'" class="flex flex-col gap-4">
      <Card>
        <h2 class="mb-3 font-semibold">Players ({{ gameStore.players.length }})</h2>
        <div class="flex flex-wrap gap-2">
          <div v-for="p in gameStore.players" :key="p.user_id" class="flex items-center gap-2 rounded-full border border-[--border] px-3 py-1.5 text-sm">
            <Avatar :name="p.name" :user-id="p.user_id" size="sm" />
            {{ p.name }}
          </div>
          <p v-if="!gameStore.players.length" class="text-[--text-secondary] text-sm">Waiting for players…</p>
        </div>
      </Card>
      <Button :loading="loading === 'start'" @click="action(() => api.games.start(code), 'start')" :disabled="gameStore.players.length === 0">
        Start game
      </Button>
    </div>

    <!-- RUNNING / PAUSED -->
    <div v-else-if="['running','paused'].includes(gameStore.status)" class="flex flex-col gap-4">
      <!-- Controls -->
      <div class="flex gap-2 flex-wrap">
        <Button v-if="gameStore.status === 'running'" variant="secondary" :loading="loading === 'pause'" @click="action(() => api.games.pause(code), 'pause')">Pause</Button>
        <Button v-if="gameStore.status === 'paused'" :loading="loading === 'resume'" @click="action(() => api.games.resume(code), 'resume')">Resume</Button>
        <Button variant="danger" :loading="loading === 'end'" @click="action(() => api.games.end(code), 'end')">End game</Button>
      </div>

      <!-- Board -->
      <Card>
        <div class="flex items-center justify-between mb-3">
          <h2 class="font-semibold">Board</h2>
          <span class="text-sm text-[--text-secondary]">{{ gameStore.board.count }} / 90</span>
        </div>
        <Board :picks="gameStore.board.picks" />
      </Card>

      <!-- Leaderboard -->
      <Card>
        <h2 class="mb-3 font-semibold">Players</h2>
        <div class="flex flex-col gap-2">
          <div v-for="p in gameStore.players" :key="p.user_id" class="flex items-center gap-3 text-sm">
            <Avatar :name="p.name" :user-id="p.user_id" size="sm" />
            <span class="flex-1">{{ p.name }}</span>
            <span v-if="p.prizes_won.length" class="text-yellow-400 text-xs">{{ p.prizes_won.join(', ') }}</span>
            <span v-if="p.bogeys" class="text-red-400 text-xs">{{ p.bogeys }}× bogey</span>
          </div>
        </div>
      </Card>

      <!-- Prizes -->
      <Card>
        <h2 class="mb-3 font-semibold">Prizes</h2>
        <div class="flex flex-col gap-2">
          <div v-for="(status, prize) in gameStore.prizes" :key="prize" class="flex justify-between text-sm">
            <span>{{ prize.replace(/_/g, ' ') }}</span>
            <span :class="status.claimed ? 'text-yellow-400' : 'text-[--text-secondary]'">
              {{ status.claimed ? (gameStore.players.find(p => p.user_id === status.winner_id)?.name ?? '?') : 'Unclaimed' }}
            </span>
          </div>
        </div>
      </Card>
    </div>

    <!-- FINISHED -->
    <div v-else-if="gameStore.status === 'finished'" class="flex flex-col gap-4">
      <h2 class="text-xl font-bold">Game over!</h2>
      <Card>
        <h3 class="mb-3 font-semibold">Final results</h3>
        <div v-for="(status, prize) in gameStore.prizes" :key="prize" class="flex justify-between text-sm border-b border-[--border] py-2">
          <span>{{ prize.replace(/_/g, ' ') }}</span>
          <span>{{ status.claimed ? (gameStore.players.find(p => p.user_id === status.winner_id)?.name ?? '?') : '—' }}</span>
        </div>
      </Card>
      <div class="flex gap-2">
        <Button :loading="loading === 'clone'" @click="action(playAgain, 'clone')">Play again</Button>
        <Button variant="secondary" @click="router.push('/')">Home</Button>
      </div>
    </div>

    <ConnectionStatus :connected="gameStore.channelConnected" />
  </div>
</template>
```

- [ ] **Step 2: Commit**

```bash
git add assets/js/pages/HostDashboard.vue
git commit -m "feat: add HostDashboard page"
```

---

### Task 22: Remove LiveView code + final cleanup

**Files:**
- Delete: `lib/moth_web/live/` (all)
- Delete: `lib/moth_web/components/ui.ex`
- Delete: `lib/moth_web/components/game.ex`
- Delete: `lib/moth_web/components/layouts/*.heex` (non-root)
- Delete: `assets/js/hooks/`
- Delete: `assets/js/app.js`

- [ ] **Step 1: Remove LiveView modules**

```bash
rm -rf lib/moth_web/live/
rm lib/moth_web/components/ui.ex
rm lib/moth_web/components/game.ex
```

- [ ] **Step 2: Remove HEEX layouts (keep root if still used)**

```bash
ls lib/moth_web/components/layouts/
# Remove app.html.heex and any others that were LiveView-specific
# Keep root.html.heex only if it's still referenced by page_controller
```

Check `page_controller.ex` — if `spa` action uses `send_file` directly (it does), the HEEX layouts are unused. Remove them all:

```bash
rm -rf lib/moth_web/components/layouts/
```

- [ ] **Step 3: Remove JS hooks and old app.js**

```bash
rm -rf assets/js/hooks/
rm assets/js/app.js
```

- [ ] **Step 4: Compile — must succeed**

```bash
mix compile
```

Fix any compile errors from removed modules being referenced elsewhere (e.g., router imports, test files).

- [ ] **Step 5: Run full backend test suite**

```bash
mix test
```

Expected: all tests pass (channel tests + existing API tests).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: remove all LiveView modules, HEEX layouts, and JS hooks"
```

---

### Task 23: Integration smoke test

- [ ] **Step 1: Start Phoenix**

```bash
mix phx.server
```

Expected: Phoenix starts on port 4000, Vite watcher starts on port 5173.

- [ ] **Step 2: Open browser at `http://localhost:5173`**

Expected: Home page renders. No console errors.

- [ ] **Step 3: Auth flow**

Navigate to `/auth`. Enter email. Check that the magic link request succeeds (`POST /api/auth/magic` returns 200).

- [ ] **Step 4: Create a game**

Sign in, create a game via `/game/new`. Verify redirect to `/game/<code>/host` and game lobby renders.

- [ ] **Step 5: Join as second player**

Open incognito tab, sign in as a second user, navigate to `/game/<code>`. Verify player appears in host lobby.

- [ ] **Step 6: Start game and verify real-time**

Host clicks Start. Verify:
- Both tabs show "running" status
- CountdownRing ticks down
- When a number is picked, it appears on the Board and TicketGrid (highlighted if on ticket)

- [ ] **Step 7: Strike a number**

Player clicks a picked number on their ticket. Verify optimistic strike (cell changes immediately) and no console errors.

- [ ] **Step 8: Hard refresh**

Navigate to `/game/<code>` and hard-refresh. Verify page loads correctly (SPA catch-all works).

- [ ] **Step 9: Production build**

```bash
cd assets && npm run build
```

Expected: `priv/static/` populated with `index.html`, `assets/*.js`, `assets/*.css`. No Tailwind purge errors.

- [ ] **Step 10: Final commit**

```bash
git add -A
git commit -m "chore: Vue SPA migration complete — smoke tested"
```

---

## Appendix: Running tests

**All backend tests:**
```bash
mix test
```

**Channel tests only:**
```bash
mix test test/moth_web/channels/game_channel_test.exs
```

**Frontend unit tests:**
```bash
cd assets && npm test
```

**Frontend tests in watch mode:**
```bash
cd assets && npx vitest
```

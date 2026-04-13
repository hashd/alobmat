# Mocha Frontend Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild every screen of Mocha (Tambola/Housie game) with an ultra-modern design system, micro-animations, social features (presence, reactions), and a rich host command center — all within Phoenix LiveView + Tailwind CSS.

**Architecture:** Design system foundation (CSS tokens + Tailwind config + component library) first, then backend additions, then screens rebuilt bottom-up. LiveComponents for high-frequency sections (activity feed, picked numbers). Targeted JS hooks for interactions LiveView can't handle (countdown timer, optimistic strike, confetti, floating reactions). No framework changes — pure LiveView + HEEx + Tailwind.

**Tech Stack:** Elixir/Phoenix 1.7, LiveView 0.20, Tailwind CSS 3.4, Inter font, canvas-confetti (~6KB), Phoenix Presence

**Spec:** `docs/superpowers/specs/2026-04-10-mocha-frontend-redesign-design.md`

---

## File Structure

### New Files
```
assets/css/app.css                              — CSS custom properties + Tailwind imports + animations
assets/js/hooks/index.js                        — Hook barrel export
assets/js/hooks/countdown.js                    — Circular countdown timer
assets/js/hooks/confetti.js                     — Prize win confetti
assets/js/hooks/copy_code.js                    — Click-to-copy game code
assets/js/hooks/theme_toggle.js                 — Dark mode toggle interactions
assets/js/hooks/auto_scroll.js                  — Feed auto-scroll
assets/js/hooks/floating_reaction.js            — Emoji float-up animation
assets/js/hooks/ticket_strike.js                — Optimistic strike UI
assets/js/hooks/board_sheet.js                  — Mobile board bottom sheet
assets/js/hooks/presence.js                     — Visibility change tracking
lib/mocha_web/components/ui.ex                   — General UI primitives (button, card, badge, avatar, input, modal, toast, skeleton, etc.)
lib/mocha_web/components/game.ex                 — Game-specific components (ticket_grid, ticket_cell, prize_chip, number_pill, board, countdown)
lib/mocha_web/live/game/activity_feed.ex         — LiveComponent for activity feed (stream-based)
lib/mocha_web/live/game/picked_numbers.ex        — LiveComponent for picked numbers display
```

### Modified Files
```
assets/tailwind.config.js                       — darkMode: 'class', Inter font, custom colors
assets/js/app.js                                — Import hooks, register with LiveSocket
lib/mocha_web/components/layouts/root.html.heex  — Theme script, Inter font, viewport fix, connection status
lib/mocha_web/components/layouts/app.html.heex   — Responsive container, toast container
lib/mocha_web/components/layouts.ex              — Import new component modules
lib/mocha_web.ex                                 — Import UI + Game components in live_view/0
lib/mocha_web/router.ex                          — Return-to redirect after auth
lib/mocha_web/plugs/auth.ex                      — Store return_to in session
lib/mocha_web/live_auth.ex                       — Pass return_to on redirect
lib/mocha_web/live/home_live.ex                  — Full redesign
lib/mocha_web/live/magic_link_live.ex            — Redesign with new components
lib/mocha_web/live/profile_live.ex               — Expand with theme toggle, game history
lib/mocha_web/live/game/new_live.ex              — Redesign with segmented controls
lib/mocha_web/live/game/play_live.ex             — Full redesign (lobby + running + game over)
lib/mocha_web/live/game/host_live.ex             — Full redesign (lobby + running + game over)
lib/mocha_web/presence.ex                        — Add game-specific presence tracking
lib/mocha/game/server.ex                         — Reactions handler, server_now in pick, prize_progress in sanitize_state, auto-strike cast handler
lib/mocha/game/game.ex                           — recent_games/2, clone_game/2, send_reaction/3
lib/mocha_web/components/game_components.ex      — Deprecated (replaced by components/game.ex)
```

### Test Files
```
test/mocha/game/server_test.exs                  — Add tests for reactions, prize_progress, auto-strike cast
test/mocha/game/game_test.exs                    — Add tests for recent_games, clone_game
test/mocha_web/live/home_live_test.exs           — New: home screen LiveView tests
test/mocha_web/live/game/play_live_test.exs      — New: player view LiveView tests
test/mocha_web/live/game/host_live_test.exs      — New: host dashboard LiveView tests
```

---

## Task 1: Design System Foundation — Tailwind + CSS Tokens + Theme

**Files:**
- Modify: `assets/tailwind.config.js`
- Modify: `assets/css/app.css`
- Modify: `lib/mocha_web/components/layouts/root.html.heex`

**Spec ref:** Sections 2.1, 2.2, 2.3, 2.5 (color palette, typography, spacing, animations)

- [ ] **Step 1: Update Tailwind config**

Add `darkMode: 'class'`, extend theme with Inter font family, and add custom color references to CSS variables.

```js
// assets/tailwind.config.js
const plugin = require("tailwindcss/plugin")

module.exports = {
  darkMode: 'class',
  content: ["./js/**/*.js", "../lib/mocha_web.ex", "../lib/mocha_web/**/*.*ex"],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', '-apple-system', 'BlinkMacSystemFont', 'sans-serif'],
      },
      colors: {
        surface: 'var(--surface)',
        elevated: 'var(--elevated)',
        accent: 'var(--accent)',
        success: 'var(--success)',
        warning: 'var(--warning)',
        danger: 'var(--danger)',
        'prize-gold': 'var(--prize-gold)',
      },
      backgroundColor: {
        DEFAULT: 'var(--bg)',
      },
      textColor: {
        primary: 'var(--text-primary)',
        secondary: 'var(--text-secondary)',
        muted: 'var(--text-muted)',
      },
      borderColor: {
        DEFAULT: 'var(--border)',
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    plugin(({addBase, addUtilities}) => {
      addBase({
        "[phx-click]": { cursor: "pointer" },
      })
      addUtilities({
        ".phx-no-feedback.phx-no-feedback": {
          ".phx-no-feedback &": { display: "none" },
        },
      })
    }),
  ],
}
```

- [ ] **Step 2: Write CSS custom properties + animation keyframes**

```css
/* assets/css/app.css */
@import "tailwindcss/base";
@import "tailwindcss/components";
@import "tailwindcss/utilities";

/* === Theme tokens === */
:root {
  --bg: #FFFFFF;
  --surface: #F9FAFB;
  --elevated: #F3F4F6;
  --border: #E5E7EB;
  --text-primary: #111827;
  --text-secondary: #6B7280;
  --text-muted: #9CA3AF;
  --accent: #6366F1;
  --success: #10B981;
  --warning: #F59E0B;
  --danger: #F43F5E;
  --prize-gold: #FBBF24;
}

.dark {
  --bg: #09090B;
  --surface: #18181B;
  --elevated: #27272A;
  --border: #3F3F46;
  --text-primary: #FAFAFA;
  --text-secondary: #A1A1AA;
  --text-muted: #A1A1AA;
}

body {
  background-color: var(--bg);
  color: var(--text-primary);
}

/* === Animations (respect reduced motion) === */
@media (prefers-reduced-motion: no-preference) {
  @keyframes fade-in-up {
    from { opacity: 0; transform: translateY(8px); }
    to { opacity: 1; transform: translateY(0); }
  }
  @keyframes scale-in {
    from { opacity: 0; transform: scale(0.9); }
    to { opacity: 1; transform: scale(1); }
  }
  @keyframes bounce-in {
    0% { opacity: 0; transform: scale(0); }
    60% { transform: scale(1.05); }
    100% { opacity: 1; transform: scale(1); }
  }
  @keyframes pulse-border {
    0%, 100% { border-color: var(--warning); }
    50% { border-color: transparent; }
  }
  @keyframes shimmer {
    0% { background-position: -200% 0; }
    100% { background-position: 200% 0; }
  }
  @keyframes float-up {
    0% { opacity: 1; transform: translateY(0); }
    100% { opacity: 0; transform: translateY(-200px); }
  }
  @keyframes shake {
    0%, 100% { transform: translateX(0); }
    25% { transform: translateX(-4px); }
    75% { transform: translateX(4px); }
  }
  @keyframes strike-ripple {
    0% { box-shadow: 0 0 0 0 rgba(99, 102, 241, 0.4); }
    100% { box-shadow: 0 0 0 10px rgba(99, 102, 241, 0); }
  }
  .animate-fade-in-up { animation: fade-in-up 200ms ease-out both; }
  .animate-scale-in { animation: scale-in 200ms ease-out both; }
  .animate-bounce-in { animation: bounce-in 200ms ease-out both; }
  .animate-pulse-border { animation: pulse-border 1.5s ease-in-out infinite; }
  .animate-shimmer {
    background: linear-gradient(90deg, var(--elevated) 25%, var(--surface) 50%, var(--elevated) 75%);
    background-size: 200% 100%;
    animation: shimmer 1.5s infinite;
  }
  .animate-float-up { animation: float-up 2s ease-out forwards; }
  .animate-shake { animation: shake 200ms ease-in-out; }
  .animate-strike-ripple { animation: strike-ripple 300ms ease-out; }
}

/* Reduced motion: instant opacity only */
@media (prefers-reduced-motion: reduce) {
  .animate-fade-in-up,
  .animate-scale-in,
  .animate-bounce-in { animation: none; opacity: 1; }
  .animate-pulse-border { animation: none; }
  .animate-shimmer { animation: none; }
  .animate-float-up { animation: none; opacity: 0; }
}

/* Stagger delays (applied via style attr or utility) */
.stagger-1 { animation-delay: 50ms; }
.stagger-2 { animation-delay: 100ms; }
.stagger-3 { animation-delay: 150ms; }
.stagger-4 { animation-delay: 200ms; }
.stagger-5 { animation-delay: 250ms; }

/* === Connection status === */
#connection-status {
  display: none;
}
[phx-disconnected] #connection-status {
  display: flex;
}

/* === Page loading bar === */
.phx-page-loading .page-loading-bar {
  position: fixed; top: 0; left: 0; right: 0; height: 2px;
  background: var(--accent);
  z-index: 50;
  animation: shimmer 1s infinite;
}
```

- [ ] **Step 3: Update root layout — theme script, Inter font, viewport fix**

Replace the current `root.html.heex` with the redesigned version including the blocking theme script in `<head>`, Inter font import, fixed viewport (no user-scalable restriction), and connection status banner.

```heex
<!DOCTYPE html>
<html lang="en" class="h-full">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <.live_title><%= assigns[:page_title] || "Mocha" %></.live_title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet" />
    <link rel="stylesheet" href={~p"/assets/app.css"} />
    <script>
      // Blocking: apply theme before first paint to prevent FOUC
      (function() {
        var theme = localStorage.getItem('mocha-theme');
        if (theme === 'dark' || (!theme && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
          document.documentElement.classList.add('dark');
        }
      })();
    </script>
    <script defer src={~p"/assets/app.js"}></script>
  </head>
  <body class="h-full bg-[var(--bg)] text-[var(--text-primary)] font-sans antialiased">
    <div class="page-loading-bar hidden"></div>
    <div id="connection-status" class="fixed top-0 inset-x-0 z-50 flex items-center justify-center gap-2 bg-accent/90 text-white py-2 text-sm font-medium" role="alert">
      <svg class="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" class="opacity-25"></circle><path d="M4 12a8 8 0 018-8" stroke="currentColor" stroke-width="4" stroke-linecap="round" class="opacity-75"></path></svg>
      Connection lost. Reconnecting...
    </div>
    <%= @inner_content %>
  </body>
</html>
```

- [ ] **Step 4: Verify — compile and check in browser**

Run: `mix compile && mix phx.server`
Expected: App loads with Inter font, light mode by default, no errors. Adding `dark` class to `<html>` via DevTools flips to dark theme.

- [ ] **Step 5: Commit**

```bash
git add assets/tailwind.config.js assets/css/app.css lib/mocha_web/components/layouts/root.html.heex
git commit -m "feat: design system foundation — tokens, theme, animations, Tailwind config"
```

---

## Task 2: UI Component Library

**Files:**
- Create: `lib/mocha_web/components/ui.ex`
- Modify: `lib/mocha_web.ex`
- Modify: `lib/mocha_web/components/layouts.ex`
- Modify: `lib/mocha_web/components/layouts/app.html.heex`

**Spec ref:** Section 2.4 (component primitives)

- [ ] **Step 1: Create `MochaWeb.Components.UI` module**

Build all general-purpose function components: `button`, `card`, `badge`, `avatar`, `input_field`, `modal`, `toast`, `skeleton`, `segmented_control`, `bottom_sheet`, `connection_status`. Each component uses the CSS custom properties and Tailwind classes from Task 1.

Key implementation details:
- `avatar/1`: Compute deterministic background color from user ID hash using `rem(:erlang.phash2(id), 8)` mapping to 8 preset colors. Extract initials from name.
- `button/1`: Accept `variant` (primary/secondary/ghost/danger), `size` (sm/md/lg), `loading` (boolean). When loading, show spinner SVG and disable.
- `badge/1`: Accept `variant` (live/paused/finished/default). Live variant gets the `animate-pulse-border` class.
- `skeleton/1`: Accept `variant` (text/card/avatar/ticket). Uses `animate-shimmer` class.
- `segmented_control/1`: Accept `options` (list of `%{value, label}`), `selected`, `name`. Renders pill group with indigo fill on selected.
- `toast/1`: Accept `variant` (success/error/info), `message`. Positioned fixed top-right. Auto-dismiss via `phx-remove` after 4s.

- [ ] **Step 2: Update `mocha_web.ex` to import UI components**

In the `html_helpers/0` function, add `import MochaWeb.Components.UI` so all LiveViews and components can use `<.button>`, `<.card>`, etc.

- [ ] **Step 3: Update app layout**

Replace the app layout with a responsive container that matches the spec's spacing/max-width:

```heex
<%# lib/mocha_web/components/layouts/app.html.heex %>
<main class="mx-auto max-w-md px-4 py-6 md:max-w-4xl md:px-6">
  <div id="toast-container" class="fixed top-4 right-4 z-50 flex flex-col gap-2" aria-live="polite"></div>
  <.flash_group flash={@flash} />
  <%= @inner_content %>
</main>
```

- [ ] **Step 4: Verify — compile, smoke test components**

Run: `mix compile`
Expected: Clean compile with no errors. Components are importable in any LiveView.

- [ ] **Step 5: Commit**

```bash
git add lib/mocha_web/components/ui.ex lib/mocha_web.ex lib/mocha_web/components/layouts.ex lib/mocha_web/components/layouts/app.html.heex
git commit -m "feat: UI component library — button, card, badge, avatar, input, toast, skeleton, etc."
```

---

## Task 3: JS Hooks

**Files:**
- Create: `assets/js/hooks/index.js`
- Create: `assets/js/hooks/countdown.js`
- Create: `assets/js/hooks/confetti.js`
- Create: `assets/js/hooks/copy_code.js`
- Create: `assets/js/hooks/theme_toggle.js`
- Create: `assets/js/hooks/auto_scroll.js`
- Create: `assets/js/hooks/floating_reaction.js`
- Create: `assets/js/hooks/ticket_strike.js`
- Create: `assets/js/hooks/board_sheet.js`
- Create: `assets/js/hooks/presence.js`
- Modify: `assets/js/app.js`

**Spec ref:** Section 2.6 (JS hooks)

- [ ] **Step 1: Create each hook file**

Each hook is a separate file exporting a LiveView hook object `{ mounted(), updated(), destroyed() }`.

Key hooks and their behavior:

**`countdown.js`**: On `mounted()`, reads `data-next-pick-at` and `data-server-now` attributes. Computes delta between server time and `next_pick_at`. Runs `requestAnimationFrame` loop drawing an SVG circle arc that depletes. Updates inner text with seconds remaining. On `updated()`, reads new attributes and resets. Freezes when `data-status="paused"`. Resumes on `data-status="running"`.

**`ticket_strike.js`**: On `mounted()`, attaches click listener to the hook element. On click: (1) adds `striking` CSS class immediately (triggers amber→indigo transition), (2) tracks number in `inFlight` Set, (3) pushes `strike_out` event to server via `this.pushEvent()`. On `updated()`, checks if the server confirmed or rejected the strike via `data-strike-result` attribute. If rejected, removes `striking` class and adds `animate-shake`. Auto-strike: listens for `phx:pick` custom events, checks if number is on ticket and not already struck, fires strike automatically.

**`floating_reaction.js`**: Maintains array of active reaction `<span>` elements. On receiving a reaction event via `this.handleEvent("reaction", ...)`, creates a `<span>` with the emoji, random x-offset (10-90% of container width), applies `animate-float-up` class. After animation ends (2s), removes the element. If array length > 20, removes oldest.

**`copy_code.js`**: On click, writes `data-code` to clipboard via `navigator.clipboard.writeText()`. Shows a brief "Copied!" tooltip by toggling a CSS class for 1.5s. Falls back to `document.execCommand('copy')` for older browsers.

**`theme_toggle.js`**: On `mounted()`, sets initial state from `localStorage`. On toggle event, flips `dark` class on `<html>`, writes to `localStorage`, pushes event to server for UI state sync.

**`auto_scroll.js`**: On `updated()`, scrolls container to bottom with `scrollTo({ top: scrollHeight, behavior: 'smooth' })`.

**`board_sheet.js`**: Controls open/close of the bottom sheet. Toggles `translate-y-full` ↔ `translate-y-0` via CSS transform. Close button and backdrop click both trigger close. Touch events on drag handle compute swipe delta — if >30% of sheet height, dismiss.

**`confetti.js`**: On `mounted()`, dynamically imports `canvas-confetti` via `import()`. On receiving `confetti` event, fires a 2-3s burst with default settings.

**`presence.js`**: On `mounted()`, listens for `visibilitychange` on `document`. When page becomes hidden, starts 30s timer. If timer fires, pushes `away` event to server. When page becomes visible again, cancels timer and pushes `online` event.

- [ ] **Step 2: Create barrel export `assets/js/hooks/index.js`**

```js
import Countdown from "./countdown"
import Confetti from "./confetti"
import CopyCode from "./copy_code"
import ThemeToggle from "./theme_toggle"
import AutoScroll from "./auto_scroll"
import FloatingReaction from "./floating_reaction"
import TicketStrike from "./ticket_strike"
import BoardSheet from "./board_sheet"
import Presence from "./presence"

export default {
  Countdown,
  Confetti,
  CopyCode,
  ThemeToggle,
  AutoScroll,
  FloatingReaction,
  TicketStrike,
  BoardSheet,
  Presence,
}
```

- [ ] **Step 3: Update `assets/js/app.js` to register hooks**

```js
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import Hooks from "./hooks"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

liveSocket.connect()
window.liveSocket = liveSocket
```

- [ ] **Step 4: Verify — compile assets, check browser console**

Run: `mix phx.server`
Expected: No JS console errors. Hooks registered (check `window.liveSocket.hooks`).

- [ ] **Step 5: Commit**

```bash
git add assets/js/hooks/ assets/js/app.js
git commit -m "feat: JS hooks — countdown, strike, confetti, reactions, copy, theme, presence"
```

---

## Task 4: Backend — Small Additions

**Files:**
- Modify: `lib/mocha/game/server.ex`
- Modify: `lib/mocha/game/game.ex`
- Modify: `test/mocha/game/server_test.exs`
- Modify: `test/mocha/game/game_test.exs`

**Spec ref:** Section 6 (backend additions)

- [ ] **Step 1: Write test for `prize_progress` in `sanitize_state`**

In `test/mocha/game/server_test.exs`, add a test that starts a game, joins a player, starts the game (so tickets are assigned), strikes some numbers, and asserts that `Game.game_state(code)` includes a `prize_progress` map with the correct counts for each prize.

```elixir
test "game_state includes prize_progress per player", %{code: code, host_id: host_id} do
  player_id = 2
  Game.join_game(code, player_id)
  Game.start_game(code, host_id)
  {:ok, state} = Game.game_state(code)
  assert is_map(state.prize_progress)
  assert is_map(state.prize_progress[player_id])
  # Each prize has {struck, required}
  assert {0, 5} = state.prize_progress[player_id][:top_line]
end
```

- [ ] **Step 2: Implement `prize_progress` in `sanitize_state`**

In `server.ex`, within `sanitize_state/1`, add a `prize_progress` field that computes per-player progress for each enabled prize. For each player with a ticket, compute how many of the required numbers are struck:

```elixir
defp compute_prize_progress(tickets, struck, prizes) do
  Map.new(tickets, fn {user_id, ticket} ->
    user_struck = Map.get(struck, user_id, MapSet.new())
    progress = Map.new(prizes, fn {prize_type, _winner} ->
      {required, struck_count} = prize_requirement(prize_type, ticket, user_struck)
      {prize_type, {struck_count, required}}
    end)
    {user_id, progress}
  end)
end

defp prize_requirement(:top_line, ticket, struck), do: line_progress(ticket, 0, struck)
defp prize_requirement(:middle_line, ticket, struck), do: line_progress(ticket, 1, struck)
defp prize_requirement(:bottom_line, ticket, struck), do: line_progress(ticket, 2, struck)
defp prize_requirement(:early_five, _ticket, struck), do: {5, min(MapSet.size(struck), 5)}
defp prize_requirement(:full_house, ticket, struck) do
  total = MapSet.size(ticket.numbers)
  hit = MapSet.size(MapSet.intersection(ticket.numbers, struck))
  {total, hit}
end

defp line_progress(ticket, row_index, struck) do
  row_numbers = Enum.at(ticket.rows, row_index) |> Enum.reject(&is_nil/1) |> MapSet.new()
  hit = MapSet.size(MapSet.intersection(row_numbers, struck))
  {MapSet.size(row_numbers), hit}
end
```

Call `compute_prize_progress` inside `sanitize_state` and include in the returned map.

- [ ] **Step 3: Run test**

Run: `mix test test/mocha/game/server_test.exs --trace`
Expected: New test passes.

- [ ] **Step 4: Add `server_now` to pick broadcast payload**

In `server.ex`, in the `handle_info(:pick, ...)` handler, add `server_now: DateTime.utc_now()` to the broadcast payload alongside `number`, `count`, `next_pick_at`.

- [ ] **Step 5: Add auto-strike cast handler**

In `server.ex`, add a `handle_cast({:strike_out, user_id, number}, state)` clause that does the same logic as the existing `handle_call({:strike_out, ...})` but returns `{:noreply, state}` instead of `{:reply, ...}`. This allows auto-strike to use `GenServer.cast` to avoid thundering-herd.

In `game.ex`, add: `def strike_out_async(code, user_id, number)` that calls `GenServer.cast` instead of `call`.

- [ ] **Step 6: Add reactions handler**

In `server.ex`, add `reaction_timestamps: %{}` to the struct. Add `handle_call({:reaction, user_id, emoji}, _from, state)` that rate-limits at 1/sec per user (same pattern as chat) and broadcasts `{:reaction, %{user_id: user_id, emoji: emoji}}`.

In `game.ex`, add: `def send_reaction(code, user_id, emoji)`.

- [ ] **Step 7: Write test for `recent_games`**

In `test/mocha/game/game_test.exs`:

```elixir
test "recent_games returns games user participated in" do
  {:ok, user} = Auth.register(%{email: "test@test.com", name: "Test"})
  {:ok, code} = Game.create_game(user.id, %{name: "Test Game"})
  games = Game.recent_games(user.id, 5)
  assert length(games) == 1
  assert hd(games).code == code
end
```

- [ ] **Step 8: Implement `recent_games`**

In `game.ex`:

```elixir
def recent_games(user_id, limit \\ 5) do
  import Ecto.Query

  # Games where user is host OR is a player
  host_games = from(g in Record, where: g.host_id == ^user_id, select: g.id)
  player_games = from(p in Player, where: p.user_id == ^user_id, select: p.game_id)

  from(g in Record,
    where: g.id in subquery(host_games) or g.id in subquery(player_games),
    order_by: [desc: g.inserted_at],
    limit: ^limit,
    select: %{
      code: g.code,
      name: g.name,
      status: g.status,
      inserted_at: g.inserted_at
    }
  )
  |> Repo.all()
end
```

- [ ] **Step 9: Implement `clone_game`**

In `game.ex`:

```elixir
def clone_game(old_code, host_id) do
  with {:ok, pid} <- lookup(old_code) do
    state = Server.get_state(pid)
    create_game(host_id, %{name: state[:name] || "Rematch", settings: state.settings})
  end
end
```

- [ ] **Step 10: Run all tests**

Run: `mix test --trace`
Expected: All tests pass including new ones.

- [ ] **Step 11: Commit**

```bash
git add lib/mocha/game/server.ex lib/mocha/game/game.ex test/mocha/game/server_test.exs test/mocha/game/game_test.exs
git commit -m "feat: backend additions — prize progress, reactions, recent games, clone, auto-strike cast"
```

---

## Task 5: Backend — Auth Return-To Redirect

**Files:**
- Modify: `lib/mocha_web/plugs/auth.ex`
- Modify: `lib/mocha_web/live_auth.ex`
- Modify: `lib/mocha_web/controllers/auth_controller.ex`

**Spec ref:** Section 6 (unauthenticated join redirect)

- [ ] **Step 1: Store `return_to` in session on auth redirect**

In `lib/mocha_web/plugs/auth.ex`, update `require_authenticated_user` to store the current path:

```elixir
def require_authenticated_user(conn, _opts) do
  if conn.assigns[:current_user] do
    conn
  else
    conn
    |> put_session(:return_to, conn.request_path)
    |> put_flash(:error, "You must sign in to access this page.")
    |> redirect(to: "/")
    |> halt()
  end
end
```

- [ ] **Step 2: Update LiveAuth redirect to store return_to**

In `lib/mocha_web/live_auth.ex`, update the `:require_auth` clause to store the current URI:

```elixir
def on_mount(:require_auth, _params, session, socket) do
  case session["user_token"] do
    nil ->
      {:halt, socket |> Phoenix.LiveView.put_flash(:error, "Sign in to continue.") |> redirect(to: "/")}
    token ->
      case Auth.get_user_by_session_token(token) do
        nil -> {:halt, redirect(socket, to: "/")}
        user -> {:cont, assign(socket, :current_user, user)}
      end
  end
end
```

- [ ] **Step 3: Redirect to `return_to` after login**

In `auth_controller.ex`, after successful login (both magic link verify and OAuth callback), check for `return_to` in session:

```elixir
defp redirect_after_login(conn) do
  return_to = get_session(conn, :return_to)
  conn = delete_session(conn, :return_to)
  redirect(conn, to: return_to || "/")
end
```

Use `redirect_after_login(conn)` instead of `redirect(conn, to: "/")` in both `verify_magic_link` and `callback`.

- [ ] **Step 4: Verify — test login redirect flow manually**

Run: `mix phx.server`
Navigate to `/game/TEST-CODE` while logged out → should redirect to "/" with flash. Log in → should redirect back to `/game/TEST-CODE`.

- [ ] **Step 5: Commit**

```bash
git add lib/mocha_web/plugs/auth.ex lib/mocha_web/live_auth.ex lib/mocha_web/controllers/auth_controller.ex
git commit -m "feat: store return_to path in session for post-login redirect"
```

---

## Task 6: Game Components

**Files:**
- Create: `lib/mocha_web/components/game.ex`
- Modify: `lib/mocha_web.ex`

**Spec ref:** Sections 2.4, 3.6 (ticket_grid, ticket_cell, prize_chip, number_pill, board, countdown)

- [ ] **Step 1: Create `MochaWeb.Components.Game` module**

Build game-specific function components:

**`ticket_grid/1`**: Renders 3×9 grid. Accepts `ticket` (map with `rows`), `picks` (list), `struck` (list/MapSet), `interactive` (boolean), `status` (atom). Each cell rendered via `ticket_cell/1`. Grid uses CSS grid with `grid-cols-9`. Full-bleed on mobile (`p-2`), card padding on desktop (`md:p-4`). Wraps in a card with "YOUR TICKET" header. Adds `role="grid"` for accessibility.

**`ticket_cell/1`**: Renders single cell. Accepts `number` (int or nil), `picked` (boolean), `struck` (boolean), `interactive` (boolean). Four visual states:
- Empty (nil): `bg-[var(--elevated)]/30` with dotted border, empty
- Unpicked: `bg-[var(--surface)]` with `text-[var(--text-primary)]`
- Picked (actionable): `bg-warning/20 border-2 border-warning animate-pulse-border` when interactive
- Struck: `bg-accent text-white` with checkmark icon overlay

Interactive cells have `phx-hook="TicketStrike"` and `phx-click="strike_out"` with `phx-value-number`. Includes `role="gridcell"` and `aria-label` describing state.

**`prize_chip/1`**: Accepts `prize` (string key), `label` (display name), `winner` (nil or user map), `progress` ({struck, required} tuple), `current_user_id`, `enabled` (boolean). States: available (outlined), claimed-by-you (indigo), claimed-by-other (muted strikethrough), disabled. Progress shown as "4/5" text.

**`number_pill/1`**: Small circle with number. Accepts `number`, `latest` (boolean for highlight animation). Latest pill gets `animate-bounce-in` class.

**`board/1`**: 9×10 grid (numbers 1-90). Accepts `picks` (list of called numbers), `ticket_numbers` (optional Set for player's ticket dot indicator). Called numbers get `bg-accent text-white`. Latest pick gets glow ring. Uncalled are muted. Player's ticket numbers get a small dot in corner.

**`countdown_ring/1`**: SVG circle element with `phx-hook="Countdown"`. Accepts `next_pick_at`, `server_now`, `status` as data attributes. Renders as `<div>` with the hook managing the SVG animation.

- [ ] **Step 2: Import Game components in `mocha_web.ex`**

Add `import MochaWeb.Components.Game` to `html_helpers/0`.

- [ ] **Step 3: Verify compile**

Run: `mix compile`
Expected: Clean compile.

- [ ] **Step 4: Commit**

```bash
git add lib/mocha_web/components/game.ex lib/mocha_web.ex
git commit -m "feat: game components — ticket grid, prize chips, board, number pills, countdown"
```

---

## Task 7: Activity Feed LiveComponent

**Files:**
- Create: `lib/mocha_web/live/game/activity_feed.ex`

**Spec ref:** Section 3.6 (live activity feed)

- [ ] **Step 1: Create ActivityFeed LiveComponent**

Uses `Phoenix.LiveView.stream/3` for efficient DOM updates.

```elixir
defmodule MochaWeb.Game.ActivityFeed do
  use MochaWeb, :live_component

  def mount(socket) do
    {:ok, socket |> stream(:entries, []) |> assign(:filter, :all)}
  end

  def update(%{new_entry: entry}, socket) do
    {:ok, stream_insert(socket, :entries, entry, at: -1, limit: 50)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  def handle_event("filter", %{"type" => type}, socket) do
    {:noreply, assign(socket, :filter, String.to_existing_atom(type))}
  end

  def render(assigns) do
    # Renders:
    # - Desktop filter tabs: All / Chat / Events
    # - Stream-backed list with phx-update="stream"
    # - Each entry styled by type (pick, prize_claimed, bogey, chat, system)
    # - Chat input at bottom with 200-char limit
    # - aria-live="polite" on the feed container
    # Full HEEx template with stream rendering and type-based styling
  end
end
```

Each feed entry rendered based on `type`:
- `:pick` → number pill + "Number **N** picked"
- `:prize_claimed` → gold highlight + "Player claimed Prize!"
- `:bogey` → rose text + "Player invalid claim — N strikes left"
- `:chat` → avatar + message
- `:system` → muted italic

- [ ] **Step 2: Verify compile**

Run: `mix compile`

- [ ] **Step 3: Commit**

```bash
git add lib/mocha_web/live/game/activity_feed.ex
git commit -m "feat: ActivityFeed LiveComponent with stream-based rendering"
```

---

## Task 8: Home Screen Redesign

**Files:**
- Modify: `lib/mocha_web/live/home_live.ex`

**Spec ref:** Section 3.1

- [ ] **Step 1: Rewrite `home_live.ex`**

Replace entirely. Mount loads `@recent_games` via `Game.recent_games(user.id)` if authenticated. Assigns: `@current_user`, `@recent_games` (list or nil), `@code` (form input).

Template structure:
- Logo wordmark "mocha" at top center
- Game code input: large, monospace, auto-uppercase via `phx-hook` or CSS `uppercase`, `phx-submit="join_game"`
- Unauthenticated: auth buttons below (outlined pills for Google + Email)
- Authenticated: avatar dropdown top-right, "Create Game" primary button, recent games list with `<.card>` and `<.badge>` for status
- Empty state for no recent games
- All content wrapped in `animate-fade-in-up` with stagger classes

Handle events:
- `join_game` → `push_navigate(to: ~p"/game/#{code}")`
- Uses `<.skeleton variant="card">` while `@recent_games` is loading (use `assign_async` for the query)

- [ ] **Step 2: Verify in browser**

Run: `mix phx.server`
Expected: Home page renders with new design. Join form works. Auth buttons link correctly. Recent games show for logged-in users.

- [ ] **Step 3: Commit**

```bash
git add lib/mocha_web/live/home_live.ex
git commit -m "feat: redesign home screen — join-first, recent games, auth buttons"
```

---

## Task 9: Auth & Profile Screens

**Files:**
- Modify: `lib/mocha_web/live/magic_link_live.ex`
- Modify: `lib/mocha_web/live/profile_live.ex`

**Spec ref:** Sections 3.2, 3.3

- [ ] **Step 1: Redesign `magic_link_live.ex`**

Two states tracked via `@state` assign (`:request` or `:sent`).

Request state: centered `<.card>` with `<.input_field type="email">`, primary `<.button>` that shows loading spinner on submit, Google OAuth link below, back button top-left.

Sent state: envelope icon (SVG inline), "Check your inbox" heading, email displayed, resend button with 30s cooldown tracked via `@resend_cooldown` (decremented by `Process.send_after`), "Try a different email" link resets to `:request`.

- [ ] **Step 2: Expand `profile_live.ex`**

Mount loads `@recent_games`, `@theme` (from session/assigns), `@editing_name` (boolean).

Template:
- Large `<.avatar size="lg">` with user initials
- Display name with inline edit (click → input appears, blur → saves via `handle_event("update_name")` calling `Auth.update_user`)
- `<.segmented_control>` for theme (light/dark/system) with `phx-hook="ThemeToggle"`
- Recent games list reusing same card pattern as home screen
- Sign out button with inline confirmation

- [ ] **Step 3: Verify in browser**

Both screens render correctly with new design. Magic link flow works. Profile saves name, theme toggle works.

- [ ] **Step 4: Commit**

```bash
git add lib/mocha_web/live/magic_link_live.ex lib/mocha_web/live/profile_live.ex
git commit -m "feat: redesign auth and profile screens"
```

---

## Task 10: Game Creation Screen

**Files:**
- Modify: `lib/mocha_web/live/game/new_live.ex`

**Spec ref:** Section 3.4

- [ ] **Step 1: Rewrite `new_live.ex`**

Replace number inputs with `<.segmented_control>` for pick speed (15/30/45/60) and bogey tolerance (1/3/5). Replace raw prize list with `<.prize_chip>` toggles for the 5 built-in prizes.

Mount assigns: `@form` (with defaults), `@interval` (30), `@bogey_limit` (3), `@prizes` (MapSet of all 5 enabled by default).

Template:
- Back button top-left (`push_navigate(to: ~p"/")`)
- "Create a Game" heading
- Game name `<.input_field>` with placeholder
- Pick speed `<.segmented_control options={[...]} selected={@interval}>`
- Bogey tolerance `<.segmented_control>`
- Prizes section: 5 `<.prize_chip>` components, tappable to toggle
- Create `<.button variant="primary" loading={@creating}>`

Handle events:
- `toggle_prize` → toggles prize in `@prizes` MapSet
- `select_interval` / `select_bogey` → updates assigns
- `create` → calls `Game.create_game/2`, on success `push_navigate` to `/game/:code/host`

- [ ] **Step 2: Verify in browser**

Create game flow works. Segmented controls select correctly. Prize toggles work. Game created successfully.

- [ ] **Step 3: Commit**

```bash
git add lib/mocha_web/live/game/new_live.ex
git commit -m "feat: redesign game creation with segmented controls and prize toggles"
```

---

## Task 11: Player View — Full Redesign

**Files:**
- Modify: `lib/mocha_web/live/game/play_live.ex`

**Spec ref:** Sections 3.5 (lobby), 3.6 (gameplay), 3.8 (game over), 3.9 (error/loading)

This is the largest task. PlayLive renders three states based on `@status`: `:lobby`, `:running`/`:paused`, `:finished`.

- [ ] **Step 1: Restructure mount**

On mount:
- Subscribe to PubSub `"game:#{code}"`
- Join game via `Game.join_game(code, user_id)`
- Track presence via `MochaWeb.Presence.track/3`
- Assign all state: `@code`, `@status`, `@ticket`, `@picks`, `@struck`, `@prizes`, `@prize_progress`, `@auto_strike`, `@game_state`
- Initialize activity feed stream: `stream(:feed, [])`
- Handle `:game_not_found` → error redirect with flash

- [ ] **Step 2: Implement lobby state render**

When `@status == :lobby`:
- "You're in!" card with `animate-fade-in-up`
- Player count + avatar row (from presence data)
- "Waiting for host to start" with pulsing dots
- Prize list (read-only chips)

- [ ] **Step 3: Implement running state render**

When `@status in [:running, :paused]`:
- **Status bar**: sticky top with game code (CopyCode hook), `<.badge>` for status, `<.countdown_ring>`, settings gear
- **Ticket**: `<.ticket_grid>` with all props from assigns
- **Prizes**: horizontal scroll of `<.prize_chip>` with progress from `@prize_progress`
- **Picked numbers**: `<.number_pill>` grid
- **Board**: FAB button + bottom sheet on mobile, collapsible section on desktop
- **Activity feed**: `<.live_component module={ActivityFeed} id="feed" ...>`
- **Reactions bar**: 6 emoji buttons at bottom

Responsive: stacked on mobile, two-column on desktop via `md:grid md:grid-cols-[1fr_340px] md:gap-6`.

- [ ] **Step 4: Implement game over state render**

When `@status == :finished`:
- "Game Over" heading with `animate-scale-in`
- Confetti hook fires on mount (`phx-hook="Confetti"`)
- Prize winners list with `<.avatar>` and trophy icons
- Your Stats card: ticket snapshot, strike count, prizes won
- Game stats one-liner
- "Back to Home" button

- [ ] **Step 5: Implement all handle_info callbacks**

Update handlers:
- `{:pick, payload}` → update `@picks`, `@prize_progress`, add feed entry, auto-strike if enabled (using `Game.strike_out_async/3` — cast not call)
- `{:status, payload}` → update `@status`, add system feed entry
- `{:prize_claimed, payload}` → update `@prizes`, add gold feed entry, fire confetti if self
- `{:bogey, payload}` → add rose feed entry
- `{:chat, payload}` → add chat feed entry
- `{:reaction, payload}` → push event to FloatingReaction hook
- `{:new_game, payload}` → show toast with "Join" button for new game
- Handle event `"strike_out"` using string prize keys (no `to_existing_atom`)
- Handle event `"claim"` using string prize keys
- Handle event `"chat"` with 200-char trim, empty check
- Handle event `"reaction"` calling `Game.send_reaction/3`
- Handle event `"leave_game"` → navigate to home

- [ ] **Step 6: Verify in browser — full player flow**

Run through: join game → lobby → host starts → ticket appears → strike numbers → claim prize → game ends → game over screen.

- [ ] **Step 7: Commit**

```bash
git add lib/mocha_web/live/game/play_live.ex
git commit -m "feat: redesign player view — lobby, gameplay, game over with activity feed + reactions"
```

---

## Task 12: Host Dashboard — Full Redesign

**Files:**
- Modify: `lib/mocha_web/live/game/host_live.ex`

**Spec ref:** Sections 3.5 (lobby), 3.7 (command center), 3.8 (game over)

- [ ] **Step 1: Restructure mount**

Same pattern as PlayLive: subscribe to PubSub, track presence. Additionally load full player list with tickets and struck data for the leaderboard.

Verify `state.host_id == current_user.id`, redirect with error if not.

- [ ] **Step 2: Implement lobby state**

When `@status == :lobby`:
- Game code hero card with CopyCode hook + Share button (Web Share API fallback)
- Live player list with avatars + presence dots + "Host" badge on self. Capped at 20 + overflow pill.
- Settings summary (read-only) with "Edit" expandable
- Start button disabled until players > 0, shows count

- [ ] **Step 3: Implement running/paused state — command center**

Three-column desktop layout (`md:grid md:grid-cols-[280px_1fr_300px]`):

**Left column**: Board (9×10 grid on desktop, FAB on mobile) + countdown ring
**Center column**: 
- Game controls (Pause/Resume/End buttons, context-aware)
- Player leaderboard: top 20 players sorted by strikes. Each row: avatar, name, presence dot, progress bar (`X/15`), near-prize alerts. Near-prize computed in a helper function that checks each player's ticket rows against their struck numbers.
- Prize tracker: vertical list of prizes with claimed/unclaimed state

**Right column**: Activity log (stream-based, events only — no chat). Filterable tabs.

- [ ] **Step 4: Implement game over state**

- "Game Over" with confetti
- Full leaderboard (top 20)
- Prize winners
- "Play Again" button: calls `Game.clone_game(code, user_id)`, broadcasts `{:new_game, ...}` on old topic, navigates to new lobby
- "Back to Home" button

- [ ] **Step 5: Implement handle_info callbacks**

Same PubSub events as PlayLive plus:
- `{:player_joined, _}` → update player list/count, add presence
- `{:player_left, _}` → update presence to offline
- Recompute near-prize alerts on each `:pick` event
- Handle keyboard shortcuts via `phx-window-keydown`: Space → pause/resume, Escape → show end game confirmation

- [ ] **Step 6: Verify — full host flow**

Create game → lobby → players join (visible in list) → start → board updates → player strikes visible in leaderboard → prize claimed → end game → game over with play again.

- [ ] **Step 7: Commit**

```bash
git add lib/mocha_web/live/game/host_live.ex
git commit -m "feat: redesign host dashboard — command center with leaderboard, board, activity log"
```

---

## Task 13: Presence Integration

**Files:**
- Modify: `lib/mocha_web/presence.ex`
- Modify: `lib/mocha_web/live/game/play_live.ex`
- Modify: `lib/mocha_web/live/game/host_live.ex`

**Spec ref:** Section 4 (presence system)

- [ ] **Step 1: Expand `MochaWeb.Presence` module**

```elixir
defmodule MochaWeb.Presence do
  use Phoenix.Presence,
    otp_app: :mocha,
    pubsub_server: Mocha.PubSub

  def track_player(socket, code, user) do
    track(socket, "game:#{code}:presence", user.id, %{
      name: user.name,
      status: :online,
      joined_at: System.monotonic_time(:millisecond)
    })
  end

  def update_status(socket, code, user_id, status) do
    update(socket, "game:#{code}:presence", user_id, fn meta ->
      Map.put(meta, :status, status)
    end)
  end

  def list_players(code) do
    list("game:#{code}:presence")
  end
end
```

- [ ] **Step 2: Integrate in PlayLive and HostLive mount**

In both LiveViews, after mount:
```elixir
if connected?(socket) do
  MochaWeb.Presence.track_player(socket, code, socket.assigns.current_user)
  Phoenix.PubSub.subscribe(Mocha.PubSub, "game:#{code}:presence")
end
```

Add `handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket)` to update `@presences` assign.

- [ ] **Step 3: Use presence data in avatar rendering**

Pass `@presences` to avatar components. Each `<.avatar>` receives a `status` prop (`:online`, `:away`, `:offline`) that controls the presence dot color.

- [ ] **Step 4: Handle Presence JS hook events**

The `Presence` JS hook pushes `"away"` and `"online"` events. Handle in LiveView:
```elixir
def handle_event("away", _, socket) do
  MochaWeb.Presence.update_status(socket, socket.assigns.code, socket.assigns.current_user.id, :away)
  {:noreply, socket}
end

def handle_event("online", _, socket) do
  MochaWeb.Presence.update_status(socket, socket.assigns.code, socket.assigns.current_user.id, :online)
  {:noreply, socket}
end
```

- [ ] **Step 5: Verify**

Open two browser tabs as different users. Both should see each other's presence dots. Background one tab → dot turns amber after 30s. Close tab → dot turns gray.

- [ ] **Step 6: Commit**

```bash
git add lib/mocha_web/presence.ex lib/mocha_web/live/game/play_live.ex lib/mocha_web/live/game/host_live.ex
git commit -m "feat: presence system — online/away/offline status with avatar dots"
```

---

## Task 14: Reactions Frontend

**Files:**
- Modify: `lib/mocha_web/live/game/play_live.ex`
- Modify: `lib/mocha_web/live/game/host_live.ex`

**Spec ref:** Section 5 (floating reactions)

- [ ] **Step 1: Add reactions bar to PlayLive render**

At the bottom of the player view (all states), add:
```heex
<div id="reactions-container" phx-hook="FloatingReaction" class="fixed bottom-0 inset-x-0 pointer-events-none h-64 z-40">
</div>
<div class="flex justify-center gap-4 py-3 border-t border-[var(--border)]">
  <button :for={emoji <- ~w(😂 👏 😱 🔥 ❤️ 😭)} phx-click="reaction" phx-value-emoji={emoji}
    class="text-2xl hover:scale-110 transition-transform active:scale-95">
    <%= emoji %>
  </button>
</div>
```

- [ ] **Step 2: Handle reaction events**

In both PlayLive and HostLive:
```elixir
def handle_event("reaction", %{"emoji" => emoji}, socket) do
  Game.send_reaction(socket.assigns.code, socket.assigns.current_user.id, emoji)
  {:noreply, socket}
end

def handle_info({:reaction, payload}, socket) do
  {:noreply, push_event(socket, "reaction", payload)}
end
```

The `FloatingReaction` hook listens for the `"reaction"` event via `this.handleEvent("reaction", ...)` and creates the floating emoji.

- [ ] **Step 3: Verify**

Open two browser windows. Send a reaction in one → floating emoji appears in both. Send 25+ reactions rapidly → oldest capped at 20.

- [ ] **Step 4: Commit**

```bash
git add lib/mocha_web/live/game/play_live.ex lib/mocha_web/live/game/host_live.ex
git commit -m "feat: floating reactions — emoji bar with float-up animation"
```

---

## Task 15: Cleanup & Accessibility Pass

**Files:**
- Modify: `lib/mocha_web/components/game_components.ex` (deprecate / remove)
- Modify: `lib/mocha_web/components/game.ex` (add ARIA attributes)
- Modify: `lib/mocha_web/components/ui.ex` (add ARIA attributes)
- Modify: `assets/css/app.css` (verify reduced-motion)

**Spec ref:** Section 8 (accessibility)

- [ ] **Step 1: Remove old `game_components.ex`**

Delete `lib/mocha_web/components/game_components.ex`. Remove `import MochaWeb.GameComponents` from any file that still uses it (grep for it). All references should now point to `MochaWeb.Components.Game`.

- [ ] **Step 2: ARIA pass on game components**

In `game.ex`:
- `ticket_grid`: Add `role="grid"` to container, `role="row"` to each row div, `role="gridcell"` to each cell
- `ticket_cell`: Add `aria-label` describing state: `"Number #{number}, #{state_description}"` where state_description is "not called", "called, not struck", "struck", or "empty"
- `ticket_cell` (struck): Add `aria-pressed="true"`
- `prize_chip`: Add `role="button"` and `aria-label="Claim #{label}, progress #{struck}/#{required}"`

- [ ] **Step 3: ARIA pass on UI components**

In `ui.ex`:
- `modal`: Add `role="dialog"`, `aria-modal="true"`, `aria-labelledby` pointing to title
- `toast`: Container has `aria-live="polite"`, individual toasts have `role="status"`
- `connection_status`: Already has `role="alert"` from root layout
- `badge` (live): Add `aria-label="Game is live"` etc.

- [ ] **Step 4: ARIA on activity feed**

In `activity_feed.ex`: container gets `aria-live="polite"`. Prize claims get `aria-live="assertive"`.

- [ ] **Step 5: Verify reduced motion**

In browser DevTools, enable "Prefers reduced motion". All animations should degrade to opacity-only or be disabled. Confetti should not fire. Floating reactions should fade in place instead of floating up.

- [ ] **Step 6: Run full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: accessibility pass — ARIA roles, keyboard nav, reduced motion, cleanup old components"
```

---

## Summary

| Task | Description | Key Files |
|------|-------------|-----------|
| 1 | Design system foundation | tailwind.config, app.css, root layout |
| 2 | UI component library | components/ui.ex |
| 3 | JS hooks | assets/js/hooks/*.js, app.js |
| 4 | Backend additions | server.ex, game.ex |
| 5 | Auth return-to redirect | auth.ex, auth_controller.ex |
| 6 | Game components | components/game.ex |
| 7 | Activity feed LiveComponent | activity_feed.ex |
| 8 | Home screen | home_live.ex |
| 9 | Auth & profile screens | magic_link_live.ex, profile_live.ex |
| 10 | Game creation | new_live.ex |
| 11 | Player view (all states) | play_live.ex |
| 12 | Host dashboard (all states) | host_live.ex |
| 13 | Presence integration | presence.ex |
| 14 | Reactions frontend | play_live.ex, host_live.ex |
| 15 | Cleanup & accessibility | game.ex, ui.ex, app.css |

Tasks 1-7 are foundation. Tasks 8-12 are screens. Tasks 13-15 are cross-cutting features and polish. Tasks are ordered by dependency — each task builds on the previous ones.

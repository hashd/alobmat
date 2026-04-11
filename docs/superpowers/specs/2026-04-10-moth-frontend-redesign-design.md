# Moth Frontend Redesign — Design Spec

**Date**: 2026-04-10
**Status**: Revised (post-adversarial review)
**Scope**: Full redesign of all screens — home, auth, game creation, lobby, player view, host dashboard, game over

## 1. Design Goals

- **Ultra-modern, obsessively polished** — Linear/Vercel/Raycast level craft
- **Phone-first**, desktop-friendly (mix of phone and laptop users)
- **Social is essential** — players should feel co-present (avatars, reactions, presence, live feed)
- **Host is a command center** — rich dashboard with player stats, pacing controls, announcer tools
- **Light mode default** with user-togglable dark mode
- **Visual polish first** — sound/haptics deferred to a future phase
- **Micro-animations everywhere** — subtle, quick, intentional. Nothing bounces for more than 200ms. All animations respect `prefers-reduced-motion` (see Section 8).

### 1.1 Phasing

The prize system expansion (new prize types, custom prizes, drag-to-reorder) is **out of scope for v1**. V1 ships with the existing 5 built-in prizes (early five, top line, middle line, bottom line, full house) as toggle chips. The prize registry expansion will be covered in a separate spec.

## 2. Design System Foundation

### 2.1 Color Palette

CSS custom properties (`--color-bg`, `--color-surface`, `--color-text`, etc.) toggled via a `dark` class on `<html>`. Tailwind's `dark:` variant handles component styling — but only for structural differences (layout, borders), not colors. All semantic colors use CSS custom properties for consistency.

**Dark mode initialization**: A blocking `<script>` in the `<head>` (before any CSS renders) reads `localStorage` and applies the `dark` class synchronously. This prevents flash-of-wrong-theme (FOUC). The `ThemeToggle` JS hook handles subsequent toggle interactions only.

**Tailwind config**: Add `darkMode: 'class'` to `tailwind.config.js` so `dark:` variants respond to the class toggle, not OS preference.

**Light mode (default):**

| Token | Value | Usage |
|-------|-------|-------|
| `--bg` | `#FFFFFF` | Page background |
| `--surface` | `#F9FAFB` (gray-50) | Cards |
| `--elevated` | `#F3F4F6` (gray-100) | Elevated surfaces, inputs |
| `--border` | `#E5E7EB` (gray-200) | Borders |
| `--text-primary` | `#111827` (gray-900) | Headings, primary text |
| `--text-secondary` | `#6B7280` (gray-500) | Labels, secondary text |
| `--text-muted` | `#9CA3AF` (gray-400) | Hints, placeholders (non-essential decorative text only) |

**Dark mode:**

| Token | Value | Usage |
|-------|-------|-------|
| `--bg` | `#09090B` (zinc-950) | Page background |
| `--surface` | `#18181B` (zinc-900) | Cards |
| `--elevated` | `#27272A` (zinc-800) | Elevated surfaces, inputs |
| `--border` | `#3F3F46` (zinc-700) | Borders |
| `--text-primary` | `#FAFAFA` (zinc-50) | Headings, primary text |
| `--text-secondary` | `#A1A1AA` (zinc-400) | Labels, secondary text |
| `--text-muted` | `#A1A1AA` (zinc-400) | Hints, placeholders (same as secondary in dark to meet WCAG AA 4.5:1 on zinc-900) |

**Accent colors (same in both modes):**

| Token | Value | Usage |
|-------|-------|-------|
| `--accent` | `#6366F1` (indigo) | CTAs, active states, focus rings, struck cells |
| `--success` | `#10B981` (emerald) | Presence online, confirmations |
| `--warning` | `#F59E0B` (amber) | Picked-not-struck numbers, pending states |
| `--danger` | `#F43F5E` (rose) | Bogeys, end game, destructive actions |
| `--prize-gold` | `#FBBF24` | Prize highlights, celebrations |

### 2.2 Typography

- **Font**: Inter (system fallback: `-apple-system, BlinkMacSystemFont, sans-serif`)
- **Scale**: Uses Tailwind defaults — `text-xs` (12px), `text-sm` (14px), `text-base` (16px), `text-lg` (18px), `text-xl` (20px), `text-2xl` (24px), `text-4xl` (36px)
- **Weights**: Regular (400) body, Medium (500) labels, Semibold (600) headings, Bold (700) game codes / numbers
- **Game code font**: Monospace (`font-mono`) for game codes only

### 2.3 Spacing & Layout

- **Base unit**: 4px (`space-1`)
- **Content max-width**: `max-w-md` (28rem) on phone, `max-w-4xl` on desktop host dashboard
- **Card padding**: `p-4` mobile, `p-6` desktop
- **Border radius**: `rounded-xl` (12px) cards, `rounded-lg` (8px) buttons/inputs, `rounded-full` avatars/badges
- **Depth**: No box-shadows except for focus rings (`ring-2 ring-accent/50`). Depth via background color layering (flat, modern).

### 2.4 Component Primitives

All built as Phoenix function components in `MothWeb.Components.UI` (general primitives) and `MothWeb.Components.Game` (game-specific). Use LiveComponents for sections that update independently at high frequency (activity feed, picked numbers).

| Component | Description |
|-----------|-------------|
| `<.button>` | Variants: primary (indigo fill), secondary (outlined), ghost (text-only), danger (rose fill). States: default, hover, loading (spinner), disabled. Sizes: sm, md, lg. |
| `<.card>` | Layered surface with optional header/title. Border, hover state for interactive cards. |
| `<.badge>` | Status indicators: live (green pulse), paused (amber), finished (gray). Also for player counts, prize labels. |
| `<.avatar>` | Generated from user initials + deterministic background color (derived from user ID hash). Sizes: sm (24px), md (32px), lg (48px). Optional presence dot overlay. |
| `<.input>` | Themed form input with focus ring (indigo). Variants: text, number, email. |
| `<.modal>` | Centered dialog on desktop, bottom sheet on mobile. Backdrop blur. Close button always visible. Dismissible via tap-outside. Focus-trapped when open. |
| `<.toast>` | Notification toasts: success (emerald), error (rose), info (indigo). Auto-dismiss with progress bar. Stacks vertically. Used for errors, confirmations, and disconnection alerts. |
| `<.countdown>` | Circular countdown ring synced to `next_pick_at`. Depletes as time passes, resets on pick. |
| `<.number_pill>` | Picked number display: small circle (24px), entrance animation on new numbers. |
| `<.bottom_sheet>` | Mobile-specific: slides up from bottom, drag handle + close button (always visible as fallback). Uses `100dvh` for height. `touch-action: none` on sheet body to prevent iOS Safari overscroll conflicts. |
| `<.segmented_control>` | Pill-group selector for discrete options (pick speed, bogey limit, theme). Selected option has indigo fill with slide animation. |
| `<.prize_chip>` | Toggle chip for prize selection: selected (indigo fill), unselected (outlined). |
| `<.skeleton>` | Loading placeholder with shimmer animation. Variants: text line, card, avatar, ticket grid. |
| `<.connection_status>` | Banner/overlay for WebSocket disconnection and reconnection states. |

### 2.5 Micro-Animation Principles

- **Entrances**: Fade in + translate-up 4-8px, 150-200ms ease-out
- **State changes**: Color/background transitions 150ms ease
- **Number picks**: Scale 0 → 1 with subtle bounce (CSS `@keyframes`)
- **Strike-out**: Optimistic — instant press scale 0.95→1.0, background amber→indigo, brief ripple from center (see TicketStrike hook)
- **Prize claim**: Ripple outward from claim button. Confetti burst for the claiming player only. Other players see the prize chip update + gold flash.
- **Page transitions**: `phx-page-loading` thin top progress bar in indigo accent
- **Stagger**: Incremental additions only (not full renders). Capped at 20 items — beyond that, items appear instantly. E.g., lobby player list staggers up to 20 avatars, then shows "+N more" pill.
- **Constraint**: Nothing bounces for more than 200ms. Subtle, quick, intentional.
- **Reduced motion**: All animations wrapped in `@media (prefers-reduced-motion: no-preference)`. When `prefers-reduced-motion: reduce`, animations are replaced with instant opacity changes (fade only, no transforms). See Section 8.

### 2.6 JS Hooks

Minimal, targeted hooks for things CSS/LiveView can't handle:

| Hook | Purpose |
|------|---------|
| `Countdown` | Circular countdown timer. Server sends both `next_pick_at` and `server_now` in pick payload — hook computes delta to avoid clock skew. Freezes on `:paused` status, resets on `:running`. |
| `Confetti` | Short confetti burst on prize wins (canvas-confetti, ~6KB gzipped, loaded async on first use) |
| `NumberReveal` | Staggered entrance animation for picked numbers on mount (capped at 20 items) |
| `AutoScroll` | Keeps activity feed scrolled to bottom on new messages |
| `CopyCode` | Click-to-copy game code with tooltip feedback |
| `ThemeToggle` | Handles toggle interactions. Initial theme applied by blocking `<script>` in `<head>`, not this hook. |
| `FloatingReaction` | Places emoji `<span>` with CSS float-up animation. **Client-side cap: max 20 concurrent floating elements** — oldest dropped when exceeded. Uses `will-change: transform, opacity` for compositor promotion. |
| `Presence` | Tracks `visibilitychange` to report online/away status via Phoenix Presence meta updates |
| `BoardSheet` | Controls bottom-sheet for mobile board view. Opens/closes with CSS transform. Close via: drag handle swipe-down, close button tap, or backdrop tap. Always includes visible close button as fallback for iOS Safari gesture conflicts. |
| `TicketStrike` | **Optimistic strike UI.** On tap: (1) immediately plays press+color animation, (2) sends `phx-click` to server, (3) if server returns error, rolls back — cell reverts from indigo to amber with brief shake animation. Prevents double-fire by tracking in-flight strikes. |

## 3. Screen Designs

### 3.1 Home Screen

**Unauthenticated:**
- Centered single column, generous whitespace, no navbar
- Logo wordmark "moth" with subtle geometric icon at top
- **Join-first layout**: Game code input is the primary action (above auth). Large, monospace, auto-uppercase. Join button slides from arrow icon to "Join" label on valid code entry.
- **Unauthenticated join flow**: When a user enters a code without being logged in, the code is stored in the session. They are redirected to auth (magic link or Google). After successful login, they are automatically redirected to `/game/:code`.
- Auth buttons below with secondary visual weight (outlined pills): "Continue with Google", "Continue with Email"
- Content entrance: staggered fade-in + translate-up, 100ms between elements (max 5 items)
- **Loading state**: Skeleton shimmer for the page while the LiveView mounts

**Authenticated:**
- Top-right: avatar with green presence dot + dropdown (profile, sign out)
- Game code input remains the hero
- "Create Game" button below (primary indigo)
- "Recent Games" section: list of games hosted/played with live status badges (green "Live" pulse for active games). Tapping a live game rejoins. Cards stagger in on entrance.
- **Empty state**: New user with no game history sees: "No games yet — create one or join with a code!"
- **Loading state**: Skeleton cards while recent games query loads

**Backend addition**: `Game.recent_games(user_id, limit: 5)` — returns list of `%{code, name, status, player_count, prizes_won, played_at}` from `Game.Record` + `Game.Player` tables. Simple Ecto query, no new tables needed.

### 3.2 Auth — Magic Link

**Request state:**
- Single centered card with email input (auto-focused on mount)
- "Send Magic Link" primary button, morphs to spinner on submit
- Google OAuth as secondary option on same screen
- Back button (top-left)
- **Error state**: Invalid email format — inline validation message below input

**Confirmation state:**
- Envelope icon, "Check your inbox" heading
- Shows email sent to, expiry info ("expires in 10 minutes")
- Resend button with 30s cooldown (grayed out with countdown)
- "Try a different email" link

### 3.3 Profile

- Large initials avatar (deterministic color from user ID hash)
- Editable display name (inline edit, auto-saves on blur, brief checkmark confirmation). Max 30 characters. Sanitized server-side.
- Theme toggle: Light / Dark / System (segmented control, applies immediately)
- Game history: recent games with outcome summary (prizes won, date). Uses same `Game.recent_games/2` query as home screen.
- **Empty state**: "No games played yet"
- Sign out at bottom, ghost/danger style with inline "Are you sure?" confirmation

### 3.4 Game Creation

- Single card on clean background, no wizard
- **Game name**: Text input with auto-generated fun placeholder (e.g., "Friday Housie"). Max 50 characters.
- **Pick speed**: Segmented control with presets: 15s / 30s / 45s / 60s. Label underneath: "Relaxed → Fast"
- **Bogey tolerance**: Segmented control: 1 / 3 / 5. Label: "Strict → Forgiving"
- **Prizes** (v1): The existing 5 prizes as toggle chips. All enabled by default. Toggle to disable any.

| Prize | Description |
|-------|-------------|
| Early Five | First player to strike 5 numbers |
| Top Line | Complete the top row |
| Middle Line | Complete the middle row |
| Bottom Line | Complete the bottom row |
| Full House | All 15 numbers struck |

Display order is fixed (as listed above). No drag-to-reorder in v1.

- **Create button**: Arrow slides right on hover. On submit, morphs to spinner then redirects to lobby.
- **Error state**: If game creation fails, toast with error message. Button resets to default.

### 3.5 Lobby (Pre-Game)

The lobby is a render state within `HostLive` and `PlayLive` — **not a separate route**. When `@status == :lobby`, the LiveView renders the lobby UI. When the game starts, `@status` changes to `:running` and the UI transitions in-place with a CSS animation. No `live_navigate` or redirect.

**Host view (HostLive, `@status == :lobby`):**
- Game code as hero card: large, monospace, centered. Tap-to-copy (CopyCode hook with checkmark tooltip). "Share" button triggers Web Share API on supported mobile browsers, falls back to copy-to-clipboard everywhere else.
- Live player list: avatars (initials + deterministic color) with green presence dot. "Host" badge on host. Players animate in (slide from right + scale pop, 200ms) and out (fade + shrink, 150ms). **Capped at 20 visible avatars** — beyond that, show "+N more" pill.
- Waiting state: three gently pulsing dots + "Waiting for players..." text below player list
- Settings summary: compact read-only (pick speed, bogey limit, prizes enabled). "Edit" opens an inline expandable form within the same card (collapse/expand transition, no modal).
- Start button: disabled until at least 1 non-host player joined. Shows dynamic count: "Start Game (4 players)". Indigo fill.
- **Empty state**: "Share the code above to invite players"

**Player view (PlayLive, `@status == :lobby`):**
- "You're in!" confirmation card
- Player count + compact avatar row of other players (capped at 20 + overflow pill)
- "Waiting for host to start" with pulsing dots
- Prize list (read-only) so players know what to aim for
- **Loading state**: Skeleton card while `Game.game_state/1` resolves

**Game start transition:** Screen content fades out (200ms) → centered "Game starting..." text scales in (hold 800ms) → content cross-fades to the running game UI. This is driven by the `@status` assign change from `:lobby` to `:running`, which triggers a re-render with transition CSS classes.

### 3.6 Player View (Core Gameplay)

The most polished screen. Three zones: status bar, ticket, activity.

**Responsive layout:**
- **Mobile**: Stacked vertically — status bar, ticket, prizes, picked numbers, activity feed, reactions
- **Desktop (>768px)**: Two columns — left (ticket + prizes), right (activity feed + picked numbers + reactions)

#### Status Bar (sticky top)
- Game code (left, tappable to copy)
- Live badge: green dot + "Live" (pulses). Changes to "Paused" (amber) or "Finished" (gray)
- Countdown ring: circular ring depleting as next pick approaches, seconds remaining inside. Resets with fill animation on pick. (`Countdown` hook — server sends `next_pick_at` AND `server_now` in pick payload to avoid clock skew. Hook freezes when status is `:paused`, resets on `:running`.)
- Settings gear (right): opens bottom sheet (mobile) / dropdown (desktop) with: auto-strike toggle, theme toggle, leave game

#### Ticket
- 3x9 grid rendered in a card with "YOUR TICKET" muted header
- **Mobile tap targets**: Ticket renders full-bleed (edge-to-edge, minimal card padding `p-2`) on phones <375px to maximize cell size. Picked (actionable) cells get `scale-105 z-10` to enlarge the tap target.
- **4 cell states:**
  - **Empty**: No number. Subtle dotted background, nearly invisible
  - **Unpicked**: Number present, not yet called. Default text on surface background
  - **Picked (actionable)**: Called but not struck. Warning/amber background, gentle pulsing border. Demands attention.
  - **Struck**: Called and marked. Accent/indigo background, white text, subtle checkmark overlay

- **Strike interaction**: Handled by `TicketStrike` JS hook for optimistic feedback. Tap → instant press scale 0.95→1.0 → background amber→indigo → brief ripple from center. If server rejects (e.g., game paused), cell reverts from indigo back to amber with a brief shake animation. Hook tracks in-flight strikes to prevent double-fire from manual + auto-strike overlap.
- **Auto-strike**: When enabled, the `TicketStrike` hook fires automatically for matching numbers on pick events. Checks if number is already struck before sending to server to avoid duplicates. Uses `GenServer.cast` (fire-and-forget) instead of `GenServer.call` to prevent thundering-herd when 100+ players auto-strike simultaneously.

#### Prizes
- Horizontal scrollable row on mobile, grid on desktop
- Each prize is a card/chip with states:
  - **Available**: Outlined, "Claim" action. Shows progress hint (e.g., "4/5").
  - **Claimed by you**: Indigo fill + "Won!" + confetti burst (on claiming player's screen only)
  - **Claimed by other**: Muted, strikethrough, winner's avatar shown. Other players see gold flash on the chip.
  - **Progress hint**: Server computes `%{prize_type => {struck_count, required_count}}` as a derived field in `sanitize_state/1`. Included in game state and updated on each pick/strike broadcast. E.g., `%{top_line: {4, 5}}` means 4 of 5 top-line numbers struck.

#### Picked Numbers
- Compact pill grid, 24px circles, most recent first
- Latest pick: scales in with bounce, briefly highlighted in indigo
- Count badge in header: "23/90"
- Mobile: horizontal scroll with fade-out edges if overflow

#### Board View
- **Desktop**: Collapsible section in right column, expanded by default
- **Mobile**: Floating action button (FAB) bottom-right corner, `#` icon. Tap opens bottom sheet (~70% screen height via `70dvh`) showing full 9x10 board (1-90). Sheet has visible close button + drag handle. Uses `touch-action: none` to prevent iOS Safari overscroll conflicts.
- **Cell states**: Called = indigo fill + white text (latest pick has glow ring fading over 2s). Not called = muted surface. On player's ticket = subtle dot indicator in corner.
- FAB pulses subtly when a new number is picked.

#### Live Activity Feed

Implemented as a LiveComponent with `Phoenix.LiveView.stream/3` for efficient append-only DOM updates without full-list diffing.

**Data structure**: Each entry is `%{id: unique_id, type: atom, timestamp: DateTime, payload: map}`. Types: `:pick`, `:prize_claimed`, `:bogey`, `:chat`, `:system`. Capped at last 50 entries — older entries pruned from the stream.

**What appears in the feed:**
- **Pick**: "Number **42** picked" with inline number pill
- **Prize claim**: "AS claimed **Top Line**!" — gold highlight, prominent
- **Bogey**: "RV invalid claim — 2 strikes left" — rose text
- **Chat**: avatar + "PM: Nice one!"
- **System**: "Game paused by host" — muted italic

**Note**: Individual strike events are **not** shown in other players' feeds. Strikes are a private action — only the striking player sees their own strike reflected on their ticket. This avoids broadcast amplification (the current GameServer correctly does not broadcast strikes).

Auto-scrolls to latest (`AutoScroll` hook). New entries fade in from bottom. Chat input at bottom of feed. Chat has a 200-character max length; empty messages are blocked client-side. Rate-limit feedback: when rate-limited, the send button briefly shakes and shows "Wait..." tooltip.

**Desktop**: Filterable tabs above feed — "All / Chat / Events"

#### Reactions Bar
- Fixed row of 6 emoji at bottom: 😂 👏 😱 🔥 ❤️ 😭
- Tap → emoji floats upward from bottom on everyone's screen, random x-offset, fading out over 2s ("rising bubbles" effect)
- CSS `@keyframes` for translate-y + opacity. `FloatingReaction` hook places `<span>`, removes after animation.
- **Client-side display cap**: Max 20 concurrent floating emoji. Oldest dropped when exceeded. Uses `will-change: transform, opacity`.
- Rate-limited: 1 per second per user
- Ephemeral: broadcast via PubSub, no persistence

#### Leave Game
Settings gear → "Leave Game" → confirmation bottom sheet: "Leave game? You can rejoin with the same code." → Confirm navigates to home. Server behavior: player stays in `players` set (ticket preserved, can rejoin). Host dashboard shows player with gray (offline) presence dot.

### 3.7 Host Dashboard (Command Center)

Fundamentally different from player view. A dashboard for running the show.

**Responsive layout:**
- **Mobile**: Stacked — controls, next pick countdown, latest picks, player leaderboard, prizes, activity log
- **Desktop (>768px)**: Three columns — left (board + countdown), center (player leaderboard + prizes), right (activity log)

#### Game Controls (always visible)
- Context-aware buttons:
  - **Lobby**: "Start Game" (indigo)
  - **Running**: "Pause" (amber) + "End Game" (rose, requires confirmation modal)
  - **Paused**: "Resume" (green) + "End Game" (rose)
  - **Finished**: "Back to Home" + "Create New Game"
- Icon + label buttons
- **Desktop keyboard shortcuts**: `Space` = pause/resume (with `preventDefault` to avoid page scroll), `Esc` = end game (with confirmation modal). Shortcuts active only when the dashboard has focus.

#### Board View
- **Desktop**: Full 9x10 grid (1-90). Called numbers in indigo, uncalled muted. Latest pick has glow animation. Always visible.
- **Mobile**: Compact "Latest picks" row showing last 5 numbers as pills + FAB to open full board bottom sheet (same design as player view)

#### Player Leaderboard
- **Capped display**: Show top 20 players sorted by progress (most struck first). If >20 players, show "+N more" footer.
- Each player row:
  - Avatar + name + presence dot (green = online, amber = away, gray = offline)
  - Progress bar: X/15 struck — horizontal bar
  - **"Close to winning" alerts**: Computed client-side on the host's LiveView process from the game state. After each pick, the host's LiveView iterates players and checks prize proximity using ticket + struck data already in state. When a player is 1 number away from any prize, a callout appears: "AS — 1 away from Full House". This requires no backend changes — the host LiveView already has access to all player tickets and struck data via `game_state`.

**Backend note**: No `:near_prize` PubSub event needed. The host's LiveView computes this locally from state data it already receives.

#### Prize Tracker
- Vertical list of all enabled prizes
- Unclaimed: open circle + name
- Claimed: checkmark + name + winner avatar + timestamp. Row flashes gold briefly on claim.

#### Activity Log
- Timestamped feed of game events (no chat — host is focused on running the game). Implemented with `stream/3`, capped at 100 entries.
- Filterable: "All / Picks / Claims / Bogeys"
- Auto-scrolls to latest. On desktop, always visible in its own column.

### 3.8 Game Over Screen

**Transition**: The `:finished` status event triggers an in-place transition (no redirect). The running game UI fades out (200ms) → "Game Over" title scales in with bounce (0.8→1.0) → confetti burst (canvas-confetti, 2-3s) → results fade in below.

#### Prize Winners
- Listed in claim order
- Each: gold trophy icon + prize name + winner avatar + name
- If current player won, their entry highlighted with indigo border
- Unclaimed prizes shown muted: "Bottom Line — unclaimed"
- Staggered reveal: 150ms delay between entries (max 5 prizes, so max 750ms total — acceptable)

#### Your Stats (Player View)
- **Ticket snapshot**: Final ticket state — struck in indigo, called-but-unstruck in amber (missed), never-called muted
- Key numbers: struck count, prizes won, bogey count, total numbers called
- Card-based, personal game receipt feel

#### Game Stats (Everyone)
- Total players, numbers picked, game duration
- Compact one-liner

#### Host Additions
- Full leaderboard: top 20 players ranked by strikes, prize badges on winners. "+N more" if >20.
- "Play Again" button: creates new game with same settings, redirects to fresh lobby.

**Play Again flow**: Host taps "Play Again" → `Game.create_game/2` called with same settings → host redirected to new lobby. A `{:new_game, %{new_code: code}}` event is broadcast on the **old** game's PubSub topic before the old GameServer terminates. Players still on the game-over screen see a toast: "Host started a new game!" with a "Join" button that navigates to the new lobby. Players who already navigated away will not see this (no push notification mechanism).

**Backend addition**: Add `Game.clone_game(old_code, host_id)` that reads the finished game's settings and calls `create_game/2`. Add `{:new_game, payload}` broadcast to the old game's topic.

#### Actions
- **Play Again** (host): one-tap new game with same config
- **Back to Home**: returns to home screen

### 3.9 Error, Loading & Reconnection States

Every screen has three additional states beyond the happy path:

#### Loading States
All screens show `<.skeleton>` placeholders during initial mount:
- **Home**: Skeleton cards for recent games
- **Lobby**: Skeleton player list
- **Player/Host view**: Skeleton ticket grid + skeleton feed
- **Game over**: Skeleton winner list

Skeletons use a shimmer animation on `--elevated` background.

#### Error States
- **Invalid game code**: "Game not found" centered message with illustration + "Back to Home" button. Shown when `Game.game_state/1` returns `{:error, :game_not_found}`.
- **Game creation failure**: Toast notification with error message. Form remains editable.
- **Prize claim error**: Toast with specific message ("Already claimed!", "Invalid claim — N strikes left", etc.). Replaces current `put_flash` with styled `<.toast>`.
- **Chat rate-limited**: Send button briefly shakes, shows "Wait..." tooltip. Message preserved in input.
- **Expired session**: Redirect to home with toast: "Session expired — please sign in again."

#### Reconnection States
LiveView's built-in reconnection handles the WebSocket layer. The UI layer:

1. **Disconnected** (WebSocket lost): `<.connection_status>` banner slides down from top — "Connection lost. Reconnecting..." with indigo pulsing indicator. Countdown timer freezes. Ticket and game controls remain visible but disabled (muted overlay).
2. **Reconnecting** (attempting): Banner stays visible. LiveView reconnects automatically with exponential backoff.
3. **Reconnected**: Banner slides up and disappears. Game state refreshes from server (LiveView remount). Toast: "Reconnected!" (auto-dismiss 2s). Countdown resumes.
4. **Failed** (server gone): After multiple retries, banner changes to: "Game unavailable. The game may have ended." with "Back to Home" button.

Implementation: CSS classes on `phx-disconnected` and `phx-connected` containers (Phoenix LiveView provides these automatically). The `<.connection_status>` component reads these classes.

#### Browser Back Button
Pressing browser back during a game navigates away (LiveView default behavior). No interception — this is consistent with "Leave Game" behavior. The player can rejoin via the game code.

## 4. Cross-Cutting: Presence System

Uses Phoenix Presence integrated into the game LiveViews.

**Integration**: On mount, each LiveView (PlayLive, HostLive) tracks the user via `Presence.track/3` on the `"game:#{code}"` topic. The `Presence` JS hook sends `visibilitychange` events as presence meta updates.

**States:**
- **Online**: Green dot — tab active, WebSocket connected
- **Away**: Amber dot — tab backgrounded >30s (tracked via `visibilitychange` in `Presence` JS hook, sent as meta update)
- **Offline**: Gray dot — WebSocket disconnected (Phoenix Presence auto-detects)

Presence dots appear on avatars everywhere: lobby, host leaderboard, game-over winners.

## 5. Cross-Cutting: Floating Reactions

1. Player taps reaction emoji
2. LiveView sends event to GameServer: `Game.send_reaction(code, user_id, emoji)`
3. GameServer `handle_call({:reaction, user_id, emoji})` — rate-limited (1/sec per user, reuses `chat_timestamps` map pattern with a separate `reaction_timestamps` map). Broadcasts `{:reaction, %{user_id: user_id, emoji: emoji}}`.
4. Every client's `handle_info({:reaction, payload})` pushes the event to the `FloatingReaction` hook
5. Hook places emoji `<span>` at bottom of screen, random x-offset, CSS `@keyframes` floats up + fades out over 2s
6. **Client-side cap**: Max 20 concurrent floating elements. Oldest removed when exceeded.
7. Ephemeral: no persistence, no storage

**Backend addition**: Add `handle_call({:reaction, ...})` to `Server` module (follows chat rate-limit pattern). Add `handle_info({:reaction, ...})` to PlayLive and HostLive.

## 6. Backend Additions Required

Scoped to what v1 needs. Prize registry, custom prizes, and near-prize server broadcasts are **deferred to a future spec**.

| Change | Description | Complexity |
|--------|-------------|------------|
| **Recent games query** | `Game.recent_games(user_id, limit)` — Ecto query joining `Game.Record` + `Game.Player` on `user_id`, returning `%{code, name, status, player_count, prizes_won, played_at}`. Ordered by `inserted_at desc`. | Small |
| **Prize progress in state** | Add `prize_progress` to `sanitize_state/1` — computes `%{prize_type => {struck_count, required_count}}` per player from their ticket rows + struck set. Returned as part of game state. | Small |
| **Reactions handler** | Add `handle_call({:reaction, user_id, emoji})` to GameServer. Rate-limited 1/sec per user via `reaction_timestamps` map. Broadcasts `{:reaction, payload}`. | Small |
| **Auto-strike as cast** | Change auto-strike from `GenServer.call` to `GenServer.cast` in PlayLive to prevent thundering-herd on picks. The GameServer already handles the state update correctly regardless of call/cast. | Trivial |
| **Presence integration** | Add `Presence.track/3` calls in PlayLive and HostLive `mount/3`. Handle `presence_diff` events for player online/away/offline status. The `MothWeb.Presence` module already exists (5 lines). | Small |
| **Play Again / Clone** | `Game.clone_game(old_code, host_id)` — reads finished game's settings, calls `create_game/2`. Broadcasts `{:new_game, %{new_code: code}}` on old game's topic. | Small |
| **Server time in pick payload** | Add `server_now: DateTime.utc_now()` to the `:pick` broadcast payload alongside `next_pick_at`. Allows Countdown hook to compute drift-free deltas. | Trivial |
| **Unauthenticated join redirect** | In `MothWeb.Plugs.Auth.require_authenticated_user/2`, store `conn.request_path` in session as `:return_to` before redirecting. After login, redirect to `:return_to` if present. | Small |

## 7. Technical Implementation Notes

- **All styling**: Tailwind CSS with custom properties for theme tokens. One CSS file with custom property definitions + Tailwind imports.
- **Components**: Split into `MothWeb.Components.UI` (button, card, badge, etc.) and `MothWeb.Components.Game` (ticket_grid, prize_chip, board, etc.).
- **LiveComponents**: Use for independently-updating sections — activity feed (stream), picked numbers, player leaderboard. This minimizes re-render scope when PubSub events arrive.
- **Responsive**: Phone-first with `md:` breakpoint (768px) for desktop layouts. Ticket grid, host dashboard, and player view get multi-column layouts on desktop.
- **JS bundle**: app.js + hooks module. canvas-confetti loaded async only when needed (~6KB gzipped).
- **No framework change**: Pure LiveView + HEEx + Tailwind + targeted JS hooks. No React/Alpine.
- **Theme**: Blocking `<script>` in `<head>` applies initial theme from `localStorage`. `ThemeToggle` hook handles subsequent toggles. `darkMode: 'class'` in `tailwind.config.js`.
- **Prize identifiers**: Prizes use string keys (e.g., `"top_line"`, `"full_house"`) in all frontend code — no `String.to_existing_atom/1`. The existing atom-based backend can convert at the boundary. This prevents atom exhaustion when custom prizes are added later.
- **PubSub contract**: The codebase uses flat topics `"game:#{code}"` with tuple-tagged events `{:event_type, payload_map}`. All frontend code follows this pattern. The backend spec's documented colon-delimited topic format (e.g., `game:CODE:pick`) does not match the actual implementation and should be updated separately.

## 8. Accessibility

### Motion Sensitivity
All animations from Section 2.5 are wrapped in:
```css
@media (prefers-reduced-motion: no-preference) { /* animations */ }
```
When `prefers-reduced-motion: reduce`:
- Stagger animations → instant appearance
- Scale/bounce entrances → opacity fade only (150ms)
- Pulsing badges → static
- Floating reactions → static emoji that fades in/out in place
- Countdown ring → static progress bar
- Confetti → disabled entirely

### Keyboard Navigation
- **Ticket grid**: `role="grid"` with `role="row"` and `role="gridcell"`. Arrow keys navigate between cells. Enter/Space triggers strike on the focused cell. `aria-pressed="true"` on struck cells.
- **Major sections**: Tab navigates between: status bar → ticket → prizes → feed → reactions. Each section is a landmark with appropriate ARIA role.
- **Bottom sheet/modal**: Focus-trapped when open. Esc closes. Focus returns to trigger element on close.
- **Host keyboard shortcuts**: `Space` = pause/resume, `Esc` = end game. Active only when dashboard has focus. `preventDefault` on Space to avoid page scroll.

### Screen Readers
- **Activity feed**: `aria-live="polite"` — new entries are announced
- **Prize claims**: `aria-live="assertive"` — prize win announcements are priority
- **Countdown**: `aria-label="Next number in N seconds"` updated periodically (every 5s, not every frame)
- **Ticket cells**: `aria-label="Number 42, called, not struck"` with state updates
- **Reactions**: `aria-hidden="true"` — decorative only
- **Connection status**: `role="alert"` — disconnect/reconnect announced immediately

### Viewport
Remove `maximum-scale=1, user-scalable=no` from the viewport meta tag. Users should be able to pinch-zoom.

### Color Contrast
All text/background combinations meet WCAG AA (4.5:1 for normal text, 3:1 for large text). The dark mode `--text-muted` has been adjusted to `#A1A1AA` (zinc-400) on `#18181B` (zinc-900) = 5.08:1 contrast ratio (passes AA).

### Browser Support
Target: Safari iOS 15+, Chrome Android (latest 2 versions), Chrome/Firefox/Safari desktop (latest 2 versions). `100dvh` for dynamic viewport height (iOS Safari). Web Share API with copy-to-clipboard fallback.

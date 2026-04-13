# Multi-Ticket Feature Design

**Date:** 2026-04-12  
**Status:** Approved

## Summary

Allow hosts to assign multiple Tambola tickets to players before a game starts. Tickets are generated as a proper strip: 6 tickets covering 1–90 exactly once. Each ticket competes independently for all prizes.

---

## Data Model

### Ticket struct

Add a UUID field to `Mocha.Game.Ticket`:

```elixir
defstruct id: nil, rows: [], numbers: MapSet.new()
```

`id` is set to `Ecto.UUID.generate()` inside `generate_strip/0`. Single-ticket generation (`generate/0`) is removed; the strip is always the unit of generation.

### `Ticket.generate_strip/0`

Returns exactly 6 `%Ticket{}` structs. Together they cover every number 1–90 exactly once. Each individual ticket still satisfies all standard Tambola constraints:
- 3 rows × 9 columns
- Exactly 5 numbers per row
- Column ranges respected (col 0: 1–9, col 1: 10–19, …, col 8: 80–90)
- Numbers sorted top-to-bottom within each column

Algorithm outline:
1. For each column, take all numbers in that range and shuffle them.
2. Distribute those numbers across 6 ticket slots with per-ticket column counts of 0–3, ensuring the sum equals the column size (9, 10, or 11).
3. For each ticket, arrange its column assignments into 3 rows such that each row has exactly 5 numbers. Retry if the row constraint cannot be satisfied.
4. Assign UUIDs to each ticket.

### GenServer state additions

```elixir
# existing, changed type:
tickets: %{ticket_id => %Ticket{}}     # was %{user_id => Ticket}

# new:
ticket_owners: %{user_id => [ticket_id]}   # ordered; first N are active
player_ticket_counts: %{user_id => integer} # 1–6, defaults to default_ticket_count
```

`struck` remains `%{user_id => MapSet.t()}` — a called number is marked against the user, and it applies to all their tickets automatically.

### Game settings

Add `default_ticket_count: integer` (1–6, default 1) to the settings map, set at game creation.

### Database

`game_players.ticket` (`:map`) is renamed to `game_players.tickets` (`{:array, :map}`). One `Player` row per user per game. At game start, only the active tickets (first `player_ticket_counts[user_id]` entries from their strip) are persisted.

---

## Backend Changes

### `join_game` (server.ex)

On first join:
1. Generate a full strip of 6 via `Ticket.generate_strip/0`.
2. Insert all 6 tickets into `state.tickets` (keyed by UUID).
3. Set `state.ticket_owners[user_id] = [id1, id2, id3, id4, id5, id6]`.
4. Set `state.player_ticket_counts[user_id] = default_ticket_count`.

On rejoin: return the player's currently active tickets (no regeneration).

### New call: `{:set_ticket_count, host_id, user_id, count}`

- Rejected unless caller is `host_id` and game status is `:lobby`.
- Validates `count` in `1..6`.
- Updates `state.player_ticket_counts[user_id]`.
- Broadcasts `{:ticket_count_updated, %{user_id: user_id, count: count}}`.

### `start_game` (server.ex)

Before starting:
1. For each player, trim `state.ticket_owners[user_id]` to the first `player_ticket_counts[user_id]` entries.
2. Remove trimmed (inactive) ticket IDs from `state.tickets`.
3. Persist only active tickets to DB as an array in `game_players.tickets`.

### Prize progress

`compute_prize_progress/3` becomes `compute_prize_progress/4`, adding `ticket_owners` as a parameter. It builds a reverse map `%{ticket_id => user_id}` to look up the owner's struck set for each ticket. Output changes from `%{user_id => prize_map}` to `%{ticket_id => prize_map}`. Each ticket's progress is computed independently against `state.struck[user_id]` (the owner's struck set).

### Claim handling

Claim message changes from `{:claim, user_id, prize_type}` to `{:claim, user_id, ticket_id, prize_type}`. Server validates `ticket_id` belongs to `user_id` before checking the prize.

### New REST endpoint

```
PUT /api/games/:code/players/:user_id/ticket_count
Body: { "count": 3 }
Requires: host bearer token
```

Delegates to `Game.set_ticket_count/4`.

---

## Frontend Changes

### New Game form (NewGame.vue)

Add a "Tickets per player" segmented control (values 1–6, default 1). Passed as `default_ticket_count` in the `POST /api/games` body.

### Host Dashboard lobby (HostDashboard.vue)

Player chips in the lobby gain:
- A ticket count badge showing current count.
- `−` / `+` buttons (disabled at 1 and 6 respectively).
- Clicking calls `PUT /api/games/:code/players/:user_id/ticket_count`.
- The `ticket_count_updated` channel event updates the displayed count live for all connected hosts.

### Game store (stores/game.ts)

- `my_ticket: Ticket | null` → `my_tickets: Ticket[]`
- `prize_progress` keyed by `ticket_id` instead of `user_id`

### GamePlay page (GamePlay.vue)

Renders one `<TicketGrid>` per entry in `my_tickets`. Each grid has a "Ticket N" label. Claim button per ticket is independent, passing `ticket_id` in the claim message.

### TicketGrid component

No structural changes. Parent renders N instances, each receiving a single ticket as a prop.

### Channel messages

**Inbound claim:**
```json
{ "event": "claim", "prize": "top_line", "ticket_id": "<uuid>" }
```

**Outbound join reply:**
```json
{ "my_tickets": [{ "id": "<uuid>", "rows": [...], "numbers": [...] }] }
```

**Outbound prize_progress:**
```json
{ "prize_progress": { "<ticket_id>": { "top_line": { "required": 5, "struck": 3 } } } }
```

---

## Constraints

- Max 6 tickets per player (hard cap, enforced in server and API).
- Ticket counts can only be changed while game is in `:lobby` status.
- Strips are generated once on join; increasing a player's count from N to M activates pre-generated tickets — no regeneration.
- The strip guarantee (1–90 once) is per-player, not across all players.

# Multi-Ticket (Strip) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow hosts to assign 1–6 tickets per player (default set at game creation), generated as a valid Tambola strip (6 tickets covering 1–90 exactly once), with each ticket independently competing for all prizes.

**Architecture:** `state.tickets` changes from `%{user_id => Ticket}` to `%{ticket_id => Ticket}`. A new `state.ticket_owners = %{user_id => [ticket_id]}` tracks ownership; `state.player_ticket_counts = %{user_id => integer}` tracks active count per player. On join, a full strip of 6 is generated; active tickets = first N. On game start, inactive tickets are trimmed from state and DB. Claims and prize progress key on `ticket_id`. Struck numbers remain per `user_id` (a called number marks all of a player's tickets).

**Tech Stack:** Elixir/Phoenix GenServer + Ecto, PostgreSQL migration, Phoenix Channels, Vue 3 + TypeScript + Pinia.

---

## File Map

**Create:**
- `priv/repo/migrations/<timestamp>_update_game_players_tickets.exs`
- `test/mocha/game/ticket_test.exs` (if not already present)

**Modify:**
- `lib/mocha/game/ticket.ex` — add `id` field, add `generate_strip/0`, private helpers
- `lib/mocha/game/player.ex` — rename field `ticket` → `tickets`, change type to `{:array, :map}`
- `lib/mocha/game/server.ex` — struct, join, set_ticket_count, start_game, strike_out, claim, sanitize_state, compute_prize_progress
- `lib/mocha/game/game.ex` — add `set_ticket_count/4`, update `claim_prize/3` → `claim_prize/4`, update `@default_settings` and `validate_settings`
- `lib/mocha_web/channels/game_channel.ex` — join reply, claim handler, new push events
- `lib/mocha_web/controllers/api/game_controller.ex` — add `set_ticket_count`, update `claim`, update `create`
- `lib/mocha_web/router.ex` — add PUT route
- `assets/js/types/domain.ts` — add `id` to `Ticket`, add `ticket_count` to `Player`, add `default_ticket_count` to `GameSettings`
- `assets/js/types/channel.ts` — update `GameJoinReply`, add new event types
- `assets/js/api/client.ts` — add `setTicketCount`, update `create`
- `assets/js/stores/game.ts` — rename `myTicket` → `myTickets`, add new handlers
- `assets/js/composables/useChannel.ts` — update `claim`, handle new events
- `assets/js/pages/NewGame.vue` — add `default_ticket_count` field
- `assets/js/pages/HostDashboard.vue` — ticket count controls per player
- `assets/js/pages/GamePlay.vue` — render multiple TicketGrid instances

---

## Task 1: DB Migration

**Files:**
- Create: `priv/repo/migrations/<timestamp>_update_game_players_tickets.exs`

- [ ] **Step 1: Generate migration file**

```bash
cd /Users/kiran/hashd/dev/alobmat
mix ecto.gen.migration update_game_players_tickets
```

Expected output: `* creating priv/repo/migrations/YYYYMMDDHHMMSS_update_game_players_tickets.exs`

- [ ] **Step 2: Write the migration** (replace generated file content)

```elixir
defmodule Mocha.Repo.Migrations.UpdateGamePlayersTickets do
  use Ecto.Migration

  def change do
    alter table(:game_players) do
      remove :ticket
      add :tickets, {:array, :map}, default: []
    end
  end
end
```

- [ ] **Step 3: Run migration**

```bash
mix ecto.migrate
```

Expected output: `== Running ... UpdateGamePlayersTickets.change/0 forward`

- [ ] **Step 4: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat: migrate game_players.ticket -> tickets array"
```

---

## Task 2: Update Player Schema

**Files:**
- Modify: `lib/mocha/game/player.ex`

- [ ] **Step 1: Update the field**

In `lib/mocha/game/player.ex`, replace:
```elixir
field :ticket, :map
```
with:
```elixir
field :tickets, {:array, :map}, default: []
```

Also update the `@derive` and `changeset` cast to include `tickets` not `ticket`:
```elixir
@derive {Jason.Encoder, only: [:id, :user_id, :tickets, :prizes_won, :bogeys]}

def changeset(player, attrs) do
  player
  |> cast(attrs, [:game_id, :user_id, :tickets, :prizes_won, :bogeys])
  |> validate_required([:game_id, :user_id])
  |> unique_constraint([:game_id, :user_id])
end
```

- [ ] **Step 2: Verify compilation**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/mocha/game/player.ex
git commit -m "feat: update Player schema to use tickets array"
```

---

## Task 3: Ticket Module — UUID + generate_strip/0

**Files:**
- Modify: `lib/mocha/game/ticket.ex`
- Create (or modify): `test/mocha/game/ticket_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/mocha/game/ticket_test.exs`:

```elixir
defmodule Mocha.Game.TicketTest do
  use ExUnit.Case, async: true

  alias Mocha.Game.Ticket

  describe "generate_strip/0" do
    test "returns exactly 6 tickets" do
      strip = Ticket.generate_strip()
      assert length(strip) == 6
    end

    test "all 90 numbers appear exactly once across the strip" do
      strip = Ticket.generate_strip()
      all_numbers = strip |> Enum.flat_map(fn t -> MapSet.to_list(t.numbers) end) |> Enum.sort()
      assert all_numbers == Enum.to_list(1..90)
    end

    test "each ticket has exactly 15 numbers" do
      strip = Ticket.generate_strip()
      Enum.each(strip, fn ticket ->
        assert MapSet.size(ticket.numbers) == 15
      end)
    end

    test "each row has exactly 5 numbers" do
      strip = Ticket.generate_strip()
      Enum.each(strip, fn ticket ->
        Enum.each(ticket.rows, fn row ->
          count = Enum.count(row, &(&1 != nil))
          assert count == 5, "Row #{inspect(row)} does not have 5 numbers"
        end)
      end)
    end

    test "each ticket has a unique binary UUID" do
      strip = Ticket.generate_strip()
      ids = Enum.map(strip, & &1.id)
      assert length(Enum.uniq(ids)) == 6
      Enum.each(ids, fn id ->
        assert is_binary(id) and byte_size(id) == 36
      end)
    end

    test "numbers respect column ranges" do
      strip = Ticket.generate_strip()
      Enum.each(strip, fn ticket ->
        for col <- 0..8 do
          {low, high} = Ticket.column_range(col)
          col_nums = Enum.flat_map(ticket.rows, fn row -> [Enum.at(row, col)] end) |> Enum.reject(&is_nil/1)
          Enum.each(col_nums, fn n ->
            assert n >= low and n <= high,
                   "Number #{n} in col #{col} is outside range #{low}-#{high}"
          end)
        end
      end)
    end

    test "generate_strip/0 is deterministically valid across 5 runs" do
      for _ <- 1..5 do
        strip = Ticket.generate_strip()
        all_numbers = strip |> Enum.flat_map(fn t -> MapSet.to_list(t.numbers) end) |> Enum.sort()
        assert all_numbers == Enum.to_list(1..90)
      end
    end
  end

  describe "to_map/1 includes id" do
    test "id is present in to_map output" do
      [ticket | _] = Ticket.generate_strip()
      map = Ticket.to_map(ticket)
      assert Map.has_key?(map, "id")
      assert map["id"] == ticket.id
    end
  end

  describe "from_map/1 restores id" do
    test "round-trips id through to_map/from_map" do
      [ticket | _] = Ticket.generate_strip()
      map = Ticket.to_map(ticket)
      restored = Ticket.from_map(map)
      assert restored.id == ticket.id
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/mocha/game/ticket_test.exs
```

Expected: multiple failures (`generate_strip/0 is undefined`).

- [ ] **Step 3: Update the Ticket struct and implement generate_strip/0**

Replace the full content of `lib/mocha/game/ticket.ex`:

```elixir
defmodule Mocha.Game.Ticket do
  @moduledoc """
  Pure functions for generating valid Tambola tickets and strips.

  Rules (per ticket):
  - 3 rows x 9 columns
  - Each row has exactly 5 numbers and 4 blanks
  - Column 0: 1-9, Column 1: 10-19, ..., Column 8: 80-90
  - Numbers within a column are sorted top to bottom
  - 15 unique numbers total

  A strip is 6 tickets whose numbers together cover 1-90 exactly once.
  """

  defstruct id: nil, rows: [], numbers: MapSet.new()

  @doc "Returns the valid number range for a column index (0-8)."
  def column_range(0), do: {1, 9}
  def column_range(8), do: {80, 90}
  def column_range(col) when col in 1..7, do: {col * 10, col * 10 + 9}

  @doc "Generates a valid Tambola strip: 6 tickets covering 1–90 exactly once, each with a UUID."
  def generate_strip do
    do_generate_strip()
  end

  @doc "Converts a ticket to a serializable map."
  def to_map(%__MODULE__{id: id, rows: rows, numbers: numbers}) do
    %{"id" => id, "rows" => rows, "numbers" => MapSet.to_list(numbers)}
  end

  @doc "Restores a ticket from a map."
  def from_map(%{"id" => id, "rows" => rows, "numbers" => numbers}) do
    %__MODULE__{id: id, rows: rows, numbers: MapSet.new(numbers)}
  end

  # ── Strip generation ─────────────────────────────────────────────────────────

  defp do_generate_strip do
    # Step 1: Shuffle each column's full number range
    column_pools =
      for col <- 0..8 do
        {low, high} = column_range(col)
        Enum.to_list(low..high) |> Enum.shuffle()
      end

    # Step 2: Distribute each column's numbers across 6 ticket slots.
    # col_assignments[col] = [[nums_for_t0], [nums_for_t1], ..., [nums_for_t5]]
    col_assignments =
      Enum.map(column_pools, fn pool ->
        counts = fill_counts(List.duplicate(0, 6), length(pool), 3) |> Enum.shuffle()
        split_by_counts(pool, counts)
      end)

    # Step 3: Build per-ticket col_nums and col_counts
    tickets_data =
      for t <- 0..5 do
        col_nums = Enum.map(col_assignments, fn slots -> Enum.at(slots, t) end)
        col_counts = Enum.map(col_nums, &length/1)
        {col_nums, col_counts}
      end

    # Step 4: Assign numbers to rows (5 per row) for each ticket
    tickets =
      Enum.map(tickets_data, fn {col_nums, col_counts} ->
        rows = assign_to_rows(col_nums, col_counts)
        numbers = rows |> List.flatten() |> Enum.reject(&is_nil/1) |> MapSet.new()
        %__MODULE__{id: Ecto.UUID.generate(), rows: rows, numbers: numbers}
      end)

    # Verify 1-90 coverage (safety net)
    all_numbers =
      tickets
      |> Enum.flat_map(fn t -> MapSet.to_list(t.numbers) end)
      |> Enum.sort()

    if all_numbers == Enum.to_list(1..90) do
      tickets
    else
      do_generate_strip()
    end
  rescue
    _ -> do_generate_strip()
  end

  # Randomly fill `slots` counters summing to `total`, each capped at `max_val`.
  defp fill_counts(counts, 0, _max), do: counts

  defp fill_counts(counts, remaining, max_val) do
    eligible =
      counts
      |> Enum.with_index()
      |> Enum.filter(fn {c, _} -> c < max_val end)
      |> Enum.map(fn {_, i} -> i end)

    idx = Enum.random(eligible)
    fill_counts(List.update_at(counts, idx, &(&1 + 1)), remaining - 1, max_val)
  end

  # Split pool into sublists of sizes given by counts. Sorts each sublist (for column ordering).
  defp split_by_counts(pool, counts) do
    {_, result} =
      Enum.reduce(counts, {pool, []}, fn count, {remaining, acc} ->
        {taken, rest} = Enum.split(remaining, count)
        {rest, acc ++ [Enum.sort(taken)]}
      end)

    result
  end

  # ── Row assignment (shared by single-ticket and strip logic) ─────────────────

  defp assign_to_rows(col_numbers, col_counts) do
    row_assignments =
      col_counts
      |> Enum.with_index()
      |> Enum.map(fn {count, _col} ->
        Enum.take_random(0..2 |> Enum.to_list(), count)
      end)

    row_totals =
      Enum.reduce(row_assignments, [0, 0, 0], fn rows, acc ->
        Enum.reduce(rows, acc, fn row, a -> List.update_at(a, row, &(&1 + 1)) end)
      end)

    if row_totals == [5, 5, 5] do
      build_rows(col_numbers, row_assignments)
    else
      assign_to_rows(col_numbers, col_counts)
    end
  end

  defp build_rows(col_numbers, row_assignments) do
    for row <- 0..2 do
      for col <- 0..8 do
        rows_for_col = Enum.at(row_assignments, col)
        numbers_for_col = Enum.at(col_numbers, col)
        row_index = Enum.find_index(Enum.sort(rows_for_col), &(&1 == row))

        if row_index do
          Enum.at(numbers_for_col, row_index)
        else
          nil
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/mocha/game/ticket_test.exs
```

Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/mocha/game/ticket.ex test/mocha/game/ticket_test.exs
git commit -m "feat: add UUID to Ticket, implement generate_strip/0 for full 1-90 coverage"
```

---

## Task 4: Server Struct + Join Handler

**Files:**
- Modify: `lib/mocha/game/server.ex`

- [ ] **Step 1: Update defstruct** — add `ticket_owners` and `player_ticket_counts`, remove old `tickets` default comment

In `lib/mocha/game/server.ex`, replace the `defstruct` block:

```elixir
defstruct [
  :id,
  :code,
  :host_id,
  :timer_ref,
  :next_pick_at,
  :host_disconnect_ref,
  :started_at,
  :finished_at,
  status: :lobby,
  board: nil,
  tickets: %{},
  ticket_owners: %{},
  player_ticket_counts: %{},
  players: MapSet.new(),
  struck: %{},
  prizes: %{},
  bogeys: %{},
  settings: %{},
  chat_timestamps: %{},
  reaction_timestamps: %{}
]
```

- [ ] **Step 2: Update client API — add `set_ticket_count`, update `claim_prize`**

In the `# Client API` section of `server.ex`, replace:

```elixir
def claim_prize(pid, user_id, prize), do: GenServer.call(pid, {:claim, user_id, prize})
```

with:

```elixir
def claim_prize(pid, user_id, ticket_id, prize), do: GenServer.call(pid, {:claim, user_id, ticket_id, prize})
def set_ticket_count(pid, host_id, user_id, count), do: GenServer.call(pid, {:set_ticket_count, host_id, user_id, count})
```

- [ ] **Step 3: Update the join handler**

Replace the entire `handle_call({:join, user_id, secret}, _from, state)` clause (the non-finished one, lines ~92-118) with:

```elixir
def handle_call({:join, user_id, secret}, _from, state) do
  visibility = Map.get(state.settings, :visibility) || Map.get(state.settings, "visibility", "public")
  join_secret = Map.get(state.settings, :join_secret) || Map.get(state.settings, "join_secret")

  if visibility == "private" and user_id != state.host_id and secret != join_secret do
    {:reply, {:error, :invalid_secret}, state}
  else
    if Map.has_key?(state.ticket_owners, user_id) do
      # Rejoin: return currently active tickets
      count = Map.get(state.player_ticket_counts, user_id, 1)
      active_ids = Enum.take(state.ticket_owners[user_id], count)
      active_tickets = Enum.map(active_ids, fn tid -> state.tickets[tid] end)
      {:reply, {:ok, active_tickets}, state}
    else
      default_count = Map.get(state.settings, :default_ticket_count, 1)
      strip = Ticket.generate_strip()
      ticket_ids = Enum.map(strip, & &1.id)
      new_tickets = Map.merge(state.tickets, Map.new(strip, fn t -> {t.id, t} end))

      new_state = %{state |
        players: MapSet.put(state.players, user_id),
        tickets: new_tickets,
        ticket_owners: Map.put(state.ticket_owners, user_id, ticket_ids),
        player_ticket_counts: Map.put(state.player_ticket_counts, user_id, default_count)
      }

      if new_state.id do
        active_maps = strip |> Enum.take(default_count) |> Enum.map(&Ticket.to_map/1)
        Mocha.Repo.insert!(
          %Mocha.Game.Player{game_id: new_state.id, user_id: user_id, tickets: active_maps},
          on_conflict: :nothing
        )
      end

      broadcast(new_state.code, :player_joined, %{user_id: user_id})
      {:reply, {:ok, Enum.take(strip, default_count)}, new_state}
    end
  end
end
```

- [ ] **Step 4: Verify compilation**

```bash
mix compile
```

Expected: no errors (some warnings about unreferenced clauses are ok at this stage).

- [ ] **Step 5: Commit**

```bash
git add lib/mocha/game/server.ex
git commit -m "feat: update Server struct and join handler for multi-ticket strips"
```

---

## Task 5: Server — set_ticket_count Handler

**Files:**
- Modify: `lib/mocha/game/server.ex`

- [ ] **Step 1: Add the handler** — insert after the `handle_call({:start_game, _other_id}, ...)` fallthrough clause

```elixir
def handle_call({:set_ticket_count, host_id, user_id, count}, _from, %{host_id: host_id, status: :lobby} = state) do
  cond do
    count not in 1..6 ->
      {:reply, {:error, :invalid_count}, state}

    not Map.has_key?(state.ticket_owners, user_id) ->
      {:reply, {:error, :player_not_found}, state}

    true ->
      new_state = %{state | player_ticket_counts: Map.put(state.player_ticket_counts, user_id, count)}
      active_ids = Enum.take(new_state.ticket_owners[user_id], count)
      active_tickets = Enum.map(active_ids, fn tid -> Ticket.to_map(new_state.tickets[tid]) end)

      broadcast(new_state.code, :ticket_count_updated, %{user_id: user_id, count: count})
      broadcast(new_state.code, :player_tickets_updated, %{user_id: user_id, tickets: active_tickets})

      {:reply, :ok, new_state}
  end
end

def handle_call({:set_ticket_count, _, _, _}, _from, state) do
  {:reply, {:error, :not_host}, state}
end
```

- [ ] **Step 2: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/mocha/game/server.ex
git commit -m "feat: add set_ticket_count handler to Server"
```

---

## Task 6: Server — start_game Update

**Files:**
- Modify: `lib/mocha/game/server.ex`

- [ ] **Step 1: Replace the start_game handler**

Replace the `handle_call({:start_game, host_id}, _from, %{host_id: host_id, status: :lobby} = state)` clause with:

```elixir
def handle_call({:start_game, host_id}, _from, %{host_id: host_id, status: :lobby} = state) do
  # Trim each player's ticket_owners to their active count; remove inactive tickets
  {trimmed_owners, active_ticket_ids} =
    Enum.reduce(state.ticket_owners, {%{}, MapSet.new()}, fn {uid, ids}, {owners_acc, active_acc} ->
      count = Map.get(state.player_ticket_counts, uid, 1)
      active_ids = Enum.take(ids, count)
      {Map.put(owners_acc, uid, active_ids), MapSet.union(active_acc, MapSet.new(active_ids))}
    end)

  active_tickets = Map.filter(state.tickets, fn {id, _} -> MapSet.member?(active_ticket_ids, id) end)

  now = DateTime.utc_now() |> DateTime.truncate(:second)
  interval = Map.get(state.settings, :interval, 30)
  next_pick_at = DateTime.add(now, interval)
  timer_ref = schedule_pick(interval)

  new_state = %{state |
    status: :running,
    tickets: active_tickets,
    ticket_owners: trimmed_owners,
    started_at: now,
    timer_ref: timer_ref,
    next_pick_at: next_pick_at
  }

  if new_state.id do
    Enum.each(trimmed_owners, fn {player_id, ticket_ids} ->
      tickets_maps = Enum.map(ticket_ids, fn tid -> Ticket.to_map(active_tickets[tid]) end)
      Mocha.Repo.insert!(
        %Mocha.Game.Player{game_id: new_state.id, user_id: player_id, tickets: tickets_maps},
        on_conflict: [set: [tickets: tickets_maps]],
        conflict_target: [:game_id, :user_id]
      )
    end)
  end

  broadcast(new_state.code, :status, %{status: :running, started_at: now})
  {:reply, :ok, new_state}
end
```

- [ ] **Step 2: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/mocha/game/server.ex
git commit -m "feat: trim inactive tickets at game start"
```

---

## Task 7: Server — strike_out Update (call + cast)

**Files:**
- Modify: `lib/mocha/game/server.ex`

- [ ] **Step 1: Replace the call-based strike_out handler** (was checking `state.tickets[user_id]`, now checks across all active ticket IDs)

Replace `handle_call({:strike_out, user_id, number}, _from, state)`:

```elixir
def handle_call({:strike_out, user_id, number}, _from, state) do
  picked_set = MapSet.new(state.board.picks)
  active_ids = Map.get(state.ticket_owners, user_id, [])

  has_number =
    Enum.any?(active_ids, fn tid ->
      case Map.get(state.tickets, tid) do
        nil -> false
        ticket -> MapSet.member?(ticket.numbers, number)
      end
    end)

  cond do
    state.status not in [:running, :paused] ->
      {:reply, {:error, :game_not_running}, state}

    Enum.empty?(active_ids) ->
      {:reply, {:error, :not_in_game}, state}

    not MapSet.member?(picked_set, number) ->
      {:reply, {:error, :not_picked}, state}

    not has_number ->
      {:reply, {:error, :not_on_ticket}, state}

    true ->
      user_struck = Map.get(state.struck, user_id, MapSet.new())
      new_state = %{state | struck: Map.put(state.struck, user_id, MapSet.put(user_struck, number))}
      {:reply, :ok, new_state}
  end
end
```

- [ ] **Step 2: Replace the cast-based strike_out handler**

Replace `handle_cast({:strike_out, user_id, number}, state)`:

```elixir
def handle_cast({:strike_out, user_id, number}, state) do
  picked_set = MapSet.new(state.board.picks)
  active_ids = Map.get(state.ticket_owners, user_id, [])

  has_number =
    Enum.any?(active_ids, fn tid ->
      case Map.get(state.tickets, tid) do
        nil -> false
        ticket -> MapSet.member?(ticket.numbers, number)
      end
    end)

  cond do
    state.status not in [:running, :paused] -> {:noreply, state}
    Enum.empty?(active_ids) -> {:noreply, state}
    not MapSet.member?(picked_set, number) -> {:noreply, state}
    not has_number -> {:noreply, state}

    true ->
      user_struck = Map.get(state.struck, user_id, MapSet.new())
      new_state = %{state | struck: Map.put(state.struck, user_id, MapSet.put(user_struck, number))}
      {:noreply, new_state}
  end
end
```

- [ ] **Step 3: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/mocha/game/server.ex
git commit -m "feat: update strike_out to check across all active tickets"
```

---

## Task 8: Server — claim Handler Update

**Files:**
- Modify: `lib/mocha/game/server.ex`

- [ ] **Step 1: Replace the claim handler** — now takes `ticket_id`, validates it belongs to the user

Replace `handle_call({:claim, user_id, prize_type}, _from, state)`:

```elixir
def handle_call({:claim, user_id, ticket_id, prize_type}, _from, state) do
  bogey_limit = Map.get(state.settings, :bogey_limit, 3)
  user_bogeys = Map.get(state.bogeys, user_id, 0)
  active_ids = Map.get(state.ticket_owners, user_id, [])

  cond do
    state.status != :running ->
      {:reply, {:error, :game_not_running}, state}

    user_bogeys >= bogey_limit ->
      {:reply, {:error, :disqualified}, state}

    Enum.empty?(active_ids) ->
      {:reply, {:error, :not_in_game}, state}

    ticket_id not in active_ids ->
      {:reply, {:error, :invalid_ticket}, state}

    not Map.has_key?(state.prizes, prize_type) ->
      {:reply, {:error, :prize_not_enabled}, state}

    state.prizes[prize_type] != nil ->
      {:reply, {:error, :already_claimed}, state}

    true ->
      ticket = state.tickets[ticket_id]
      struck = Map.get(state.struck, user_id, MapSet.new())

      case Prize.check_claim(prize_type, ticket, struck) do
        :valid ->
          new_state = %{state | prizes: Map.put(state.prizes, prize_type, user_id)}

          if new_state.id do
            Mocha.Repo.update_all(
              from(p in Mocha.Game.Player,
                where: p.game_id == ^new_state.id and p.user_id == ^user_id
              ),
              push: [prizes_won: to_string(prize_type)]
            )
          end

          broadcast(new_state.code, :prize_claimed, %{prize: prize_type, winner_id: user_id})
          {:reply, {:ok, prize_type}, new_state}

        :invalid ->
          new_bogeys = user_bogeys + 1
          remaining = bogey_limit - new_bogeys
          new_state = %{state | bogeys: Map.put(state.bogeys, user_id, new_bogeys)}

          broadcast(new_state.code, :bogey, %{
            user_id: user_id,
            prize: prize_type,
            remaining: remaining
          })

          {:reply, {:error, :bogey, remaining}, new_state}
      end
  end
end
```

- [ ] **Step 2: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/mocha/game/server.ex
git commit -m "feat: update claim handler to require ticket_id"
```

---

## Task 9: Server — sanitize_state + compute_prize_progress

**Files:**
- Modify: `lib/mocha/game/server.ex`

- [ ] **Step 1: Replace sanitize_state**

```elixir
defp sanitize_state(state) do
  prize_progress = compute_prize_progress(state.tickets, state.ticket_owners, state.struck, state.prizes)

  Map.from_struct(state)
  |> Map.drop([:timer_ref, :host_disconnect_ref, :chat_timestamps, :reaction_timestamps])
  |> Map.put(:prize_progress, stringify_prize_progress(prize_progress))
  |> Map.update(:players, [], &MapSet.to_list/1)
  |> Map.update(:struck, %{}, fn struck ->
    Map.new(struck, fn {k, v} -> {k, MapSet.to_list(v)} end)
  end)
  |> Map.update(:board, nil, fn
    %Board{} = b -> Board.to_map(b)
    other -> other
  end)
  |> Map.update(:tickets, %{}, fn tickets ->
    Map.new(tickets, fn {k, %Ticket{} = t} -> {k, Ticket.to_map(t)} end)
  end)
end
```

- [ ] **Step 2: Replace stringify_prize_progress** (outer key changes from user_id to ticket_id — both are strings, logic is same)

```elixir
defp stringify_prize_progress(progress) do
  Map.new(progress, fn {ticket_id, prizes} ->
    {ticket_id, Map.new(prizes, fn {prize, val} -> {to_string(prize), val} end)}
  end)
end
```

- [ ] **Step 3: Replace compute_prize_progress** — now keyed by ticket_id, looks up owner via reverse map

```elixir
defp compute_prize_progress(tickets, ticket_owners, struck, prizes) do
  owner_of =
    Enum.flat_map(ticket_owners, fn {uid, ids} ->
      Enum.map(ids, fn tid -> {tid, uid} end)
    end)
    |> Map.new()

  Map.new(tickets, fn {ticket_id, ticket} ->
    user_id = Map.get(owner_of, ticket_id)
    user_struck = Map.get(struck, user_id, MapSet.new())

    progress =
      Map.new(prizes, fn {prize_type, _winner} ->
        {required, struck_count} = prize_requirement(prize_type, ticket, user_struck)
        {prize_type, %{struck: struck_count, required: required}}
      end)

    {ticket_id, progress}
  end)
end
```

- [ ] **Step 4: Run the full backend test suite**

```bash
mix test
```

Expected: all tests pass (or pre-existing failures only).

- [ ] **Step 5: Commit**

```bash
git add lib/mocha/game/server.ex
git commit -m "feat: update sanitize_state and compute_prize_progress for ticket_id keying"
```

---

## Task 10: Game Context + validate_settings

**Files:**
- Modify: `lib/mocha/game/game.ex`

- [ ] **Step 1: Add `default_ticket_count` to @default_settings**

```elixir
@default_settings %{
  interval: 30,
  bogey_limit: 3,
  enabled_prizes: [:early_five, :top_line, :middle_line, :bottom_line, :full_house],
  visibility: "public",
  join_secret: nil,
  default_ticket_count: 1
}
```

- [ ] **Step 2: Update validate_settings**

```elixir
defp validate_settings(settings) do
  settings
  |> Map.update(:interval, 30, &clamp(&1, 5, 120))
  |> Map.update(:bogey_limit, 3, &clamp(&1, 1, 10))
  |> Map.update(:default_ticket_count, 1, &clamp(&1, 1, 6))
end
```

- [ ] **Step 3: Update claim_prize/3 → claim_prize/4**

Replace:
```elixir
def claim_prize(code, user_id, prize) do
  with_server(code, fn pid -> Server.claim_prize(pid, user_id, prize) end)
end
```

With:
```elixir
def claim_prize(code, user_id, prize, ticket_id) do
  with_server(code, fn pid -> Server.claim_prize(pid, user_id, ticket_id, prize) end)
end
```

- [ ] **Step 4: Add set_ticket_count/4**

```elixir
def set_ticket_count(code, host_id, user_id, count) do
  with_server(code, fn pid -> Server.set_ticket_count(pid, host_id, user_id, count) end)
end
```

- [ ] **Step 5: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/mocha/game/game.ex
git commit -m "feat: update Game context for multi-ticket (claim_prize/4, set_ticket_count/4)"
```

---

## Task 11: GameController + Router

**Files:**
- Modify: `lib/mocha_web/controllers/api/game_controller.ex`
- Modify: `lib/mocha_web/router.ex`

- [ ] **Step 1: Add `default_ticket_count` to create action**

In `GameController.create`, in the `settings` map, add:
```elixir
settings = %{
  interval: params["interval"] || 30,
  bogey_limit: params["bogey_limit"] || 3,
  enabled_prizes: enabled_prizes,
  visibility: params["visibility"] || "public",
  join_secret: params["join_secret"],
  default_ticket_count: params["default_ticket_count"] || 1
}
```

- [ ] **Step 2: Update the claim action to require ticket_id**

Replace the `claim/2` action:

```elixir
def claim(conn, %{"code" => code, "prize" => prize} = params) do
  valid_prizes = ~w(early_five top_line middle_line bottom_line full_house)
  ticket_id = Map.get(params, "ticket_id")

  cond do
    is_nil(ticket_id) ->
      conn
      |> put_status(422)
      |> json(%{error: %{code: "missing_ticket_id", message: "ticket_id is required"}})

    prize not in valid_prizes ->
      conn |> put_status(422) |> json(%{error: %{code: "invalid_prize", message: "Invalid prize"}})

    true ->
      prize_atom = String.to_existing_atom(prize)

      case Game.claim_prize(String.upcase(code), conn.assigns.current_user.id, prize_atom, ticket_id) do
        {:ok, prize} ->
          json(conn, %{prize: prize})

        {:error, :already_claimed} ->
          conn
          |> put_status(409)
          |> json(%{error: %{code: "already_claimed", message: "Prize already claimed"}})

        {:error, :bogey, remaining} ->
          conn
          |> put_status(422)
          |> json(%{error: %{code: "bogey", message: "Invalid claim", remaining: remaining}})

        {:error, :disqualified} ->
          conn
          |> put_status(403)
          |> json(%{error: %{code: "disqualified", message: "You are disqualified"}})

        {:error, reason} ->
          conn
          |> put_status(422)
          |> json(%{error: %{code: to_string(reason), message: "Claim failed"}})
      end
  end
end
```

- [ ] **Step 3: Add set_ticket_count action**

```elixir
def set_ticket_count(conn, %{"code" => code, "user_id" => user_id, "count" => count})
    when is_integer(count) do
  case Game.set_ticket_count(
         String.upcase(code),
         conn.assigns.current_user.id,
         user_id,
         count
       ) do
    :ok ->
      json(conn, %{status: "ok"})

    {:error, :not_host} ->
      conn
      |> put_status(403)
      |> json(%{error: %{code: "not_host", message: "Only the host can do this"}})

    {:error, reason} ->
      conn
      |> put_status(422)
      |> json(%{error: %{code: to_string(reason), message: "Cannot set ticket count"}})
  end
end

def set_ticket_count(conn, _params) do
  conn
  |> put_status(422)
  |> json(%{error: %{code: "invalid_params", message: "count must be an integer"}})
end
```

- [ ] **Step 4: Add route in router.ex**

In the authenticated API scope, after the existing game routes, add:

```elixir
put "/games/:code/players/:user_id/ticket_count", GameController, :set_ticket_count
```

- [ ] **Step 5: Compile**

```bash
mix compile
```

Expected: no errors.

- [ ] **Step 6: Run tests**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/mocha_web/controllers/api/game_controller.ex lib/mocha_web/router.ex
git commit -m "feat: add set_ticket_count endpoint, update claim and create for multi-ticket"
```

---

## Task 12: GameChannel Update

**Files:**
- Modify: `lib/mocha_web/channels/game_channel.ex`

- [ ] **Step 1: Update the join handler to send my_tickets, include ticket_count per player**

Replace the inner join logic (from `# Enrich players` comment to `{:ok, reply, ...}`):

```elixir
user_names = Mocha.Auth.get_users_map(state.players)

players =
  Enum.map(state.players, fn uid ->
    %{
      user_id: uid,
      name: Map.get(user_names, uid, "Unknown"),
      prizes_won:
        state.prizes
        |> Enum.filter(fn {_p, winner} -> winner == uid end)
        |> Enum.map(fn {p, _} -> to_string(p) end),
      bogeys: Map.get(state.bogeys || %{}, uid, 0),
      ticket_count: Map.get(state[:player_ticket_counts] || %{}, uid, 1)
    }
  end)

# Build my_tickets: active ticket maps for this user
all_ids = Map.get(state[:ticket_owners] || %{}, current_user.id, [])
count = Map.get(state[:player_ticket_counts] || %{}, current_user.id, 1)
active_ids = Enum.take(all_ids, count)
my_tickets = Enum.map(active_ids, fn tid -> Map.get(state.tickets || %{}, tid) end) |> Enum.reject(&is_nil/1)

my_struck = get_in(state, [:struck, current_user.id]) || []

reply = %{
  code: state.code,
  name: Map.get(state, :name),
  status: to_string(state.status),
  host_id: state.host_id,
  settings: format_settings(state.settings),
  board: state.board,
  players: players,
  prizes: format_prizes(state.prizes),
  prize_progress: Map.get(state, :prize_progress, %{}),
  my_tickets: my_tickets,
  my_struck: my_struck
}

{:ok, reply, assign(socket, :game_code, code)}
```

- [ ] **Step 2: Update format_settings to include default_ticket_count**

```elixir
defp format_settings(settings) do
  %{
    interval: settings.interval,
    bogey_limit: settings.bogey_limit,
    enabled_prizes: Enum.map(settings.enabled_prizes, &to_string/1),
    default_ticket_count: Map.get(settings, :default_ticket_count, 1)
  }
end
```

- [ ] **Step 3: Add PubSub handlers for the two new events**

Add after the existing `handle_info({:player_left, ...})` clause:

```elixir
def handle_info({:ticket_count_updated, payload}, socket) do
  push(socket, "ticket_count_updated", %{user_id: payload.user_id, count: payload.count})
  {:noreply, socket}
end

def handle_info({:player_tickets_updated, payload}, socket) do
  current_user = socket.assigns.current_user
  if current_user && current_user.id == payload.user_id do
    push(socket, "my_tickets_updated", %{my_tickets: payload.tickets})
  end
  {:noreply, socket}
end
```

- [ ] **Step 4: Update the inbound claim handler to require ticket_id**

Replace `handle_in("claim", ...)`:

```elixir
def handle_in("claim", %{"prize" => prize, "ticket_id" => ticket_id}, socket) do
  valid_prizes = ~w(early_five top_line middle_line bottom_line full_house)

  if prize in valid_prizes do
    user = socket.assigns.current_user
    code = socket.assigns.game_code
    prize_atom = String.to_existing_atom(prize)

    case Game.claim_prize(code, user.id, prize_atom, ticket_id) do
      {:ok, _prize} ->
        {:noreply, socket}

      {:error, :bogey, remaining} ->
        push(socket, "claim_rejection", %{reason: "bogey", bogeys_remaining: remaining})
        {:noreply, socket}

      {:error, reason} ->
        push(socket, "claim_rejection", %{reason: to_string(reason)})
        {:noreply, socket}
    end
  else
    push(socket, "claim_rejection", %{reason: "invalid_prize"})
    {:noreply, socket}
  end
end

def handle_in("claim", _params, socket) do
  push(socket, "claim_rejection", %{reason: "missing_ticket_id"})
  {:noreply, socket}
end
```

- [ ] **Step 5: Compile and run tests**

```bash
mix compile && mix test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/mocha_web/channels/game_channel.ex
git commit -m "feat: update GameChannel for multi-ticket (my_tickets, ticket_count_updated, claim with ticket_id)"
```

---

## Task 13: TypeScript Types

**Files:**
- Modify: `assets/js/types/domain.ts`
- Modify: `assets/js/types/channel.ts`

- [ ] **Step 1: Update domain.ts**

Replace the file content:

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
  ticket_count?: number
}

export interface GameSettings {
  interval: number
  bogey_limit: number
  enabled_prizes: string[]
  default_ticket_count?: number
}

// Matches Ticket.to_map/1 — rows is 3x9 grid, null = blank cell
export interface Ticket {
  id: string
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

export interface PrizeProgress {
  struck: number
  required: number
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

- [ ] **Step 2: Update channel.ts**

Replace the file content:

```typescript
import type { Board, GameSettings, Player, PrizeProgress, PrizeStatus, Ticket } from './domain'

// ── Initial join reply ────────────────────────────────────────────────────────
export interface GameJoinReply {
  code: string
  name: string
  status: string
  settings: GameSettings
  board: Board
  players: Player[]
  prizes: Record<string, PrizeStatus>
  /** Keyed by ticket_id */
  prize_progress: Record<string, Record<string, PrizeProgress>>
  my_tickets: Ticket[]
  my_struck: number[]
  host_id?: string
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
  reason: 'bogey' | 'already_claimed' | 'disqualified' | 'invalid' | 'missing_ticket_id'
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

export interface TicketCountUpdatedEvent {
  user_id: string
  count: number
}

export interface MyTicketsUpdatedEvent {
  my_tickets: Ticket[]
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
export interface ClaimMessage { prize: string; ticket_id: string }
export interface ReactionMessage { emoji: string }
export interface ChatMessage { text: string }
```

- [ ] **Step 3: TypeScript check**

```bash
cd assets && npx tsc --noEmit 2>&1 | head -40
```

Expected: errors only in game.ts and useChannel.ts (not yet updated) — that's expected at this stage.

- [ ] **Step 4: Commit**

```bash
cd ..
git add assets/js/types/
git commit -m "feat: update TypeScript types for multi-ticket (Ticket.id, my_tickets, prize_progress)"
```

---

## Task 14: api/client.ts

**Files:**
- Modify: `assets/js/api/client.ts`

- [ ] **Step 1: Update create signature and add setTicketCount**

Replace the `games` object:

```typescript
games: {
  recent: () => request<{ games: RecentGame[] }>('GET', '/games'),
  publicGames: () => request<{ games: RecentGame[] }>('GET', '/games/public'),
  get: (code: string) => request<{ game: unknown }>('GET', `/games/${code}`),
  create: (attrs: {
    name: string
    interval: number
    bogey_limit: number
    enabled_prizes: string[]
    visibility: string
    join_secret?: string
    default_ticket_count?: number
  }) => request<{ code: string }>('POST', '/games', attrs),
  join: (code: string, secret?: string) => request<{ ticket: unknown }>('POST', `/games/${code}/join`, { secret }),
  start: (code: string) => request<void>('POST', `/games/${code}/start`),
  pause: (code: string) => request<void>('POST', `/games/${code}/pause`),
  resume: (code: string) => request<void>('POST', `/games/${code}/resume`),
  end: (code: string) => request<void>('POST', `/games/${code}/end`),
  clone: (code: string) => request<{ code: string }>('POST', `/games/${code}/clone`),
  setTicketCount: (code: string, userId: string, count: number) =>
    request<{ status: string }>('PUT', `/games/${code}/players/${userId}/ticket_count`, { count }),
},
```

- [ ] **Step 2: TypeScript check**

```bash
cd assets && npx tsc --noEmit 2>&1 | head -20
```

Expected: errors only in files not yet updated.

- [ ] **Step 3: Commit**

```bash
cd ..
git add assets/js/api/client.ts
git commit -m "feat: add setTicketCount to API client, update create signature"
```

---

## Task 15: stores/game.ts

**Files:**
- Modify: `assets/js/stores/game.ts`

- [ ] **Step 1: Rewrite the store**

```typescript
import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Board, GameSettings, Player, PrizeProgress, PrizeStatus, Ticket } from '@/types/domain'
import type {
  GameJoinReply, NumberPickedEvent, GameStatusEvent, PrizeClaimedEvent,
  BogeyEvent, PlayerJoinedEvent, PlayerLeftEvent, StrikeResultEvent,
  TicketCountUpdatedEvent, MyTicketsUpdatedEvent
} from '@/types/channel'

export const useGameStore = defineStore('game', () => {
  const code = ref('')
  const name = ref('')
  const hostId = ref<string | null>(null)
  const status = ref<string>('lobby')
  const settings = ref<GameSettings>({ interval: 30, bogey_limit: 3, enabled_prizes: [] })
  const board = ref<Board>({ picks: [], count: 0, finished: false })
  const myTickets = ref<Ticket[]>([])
  const myStruck = ref<Set<number>>(new Set())
  const players = ref<Player[]>([])
  const prizes = ref<Record<string, PrizeStatus>>({})
  const prizeProgress = ref<Record<string, Record<string, PrizeProgress>>>({})
  const nextPickAt = ref<string | null>(null)
  const channelConnected = ref(false)
  const autoStrikeEnabled = ref(false)
  const hydrated = ref(false)

  function hydrate(reply: GameJoinReply) {
    code.value = reply.code
    name.value = reply.name
    hostId.value = reply.host_id ?? null
    status.value = reply.status
    settings.value = reply.settings
    board.value = reply.board
    myTickets.value = reply.my_tickets
    myStruck.value = new Set(reply.my_struck)
    players.value = reply.players
    prizes.value = reply.prizes
    prizeProgress.value = reply.prize_progress
    channelConnected.value = true
    hydrated.value = true
  }

  function onPick(event: NumberPickedEvent, autoStrike?: (n: number) => void) {
    board.value = {
      ...board.value,
      picks: [...board.value.picks, event.number],
      count: event.count,
    }
    nextPickAt.value = event.next_pick_at

    if (autoStrikeEnabled.value && !myStruck.value.has(event.number)) {
      const onAnyTicket = myTickets.value.some(t => t.numbers.includes(event.number))
      if (onAnyTicket) autoStrike?.(event.number)
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

  function onTicketCountUpdated(event: TicketCountUpdatedEvent) {
    const player = players.value.find(p => p.user_id === event.user_id)
    if (player) player.ticket_count = event.count
  }

  function onMyTicketsUpdated(event: MyTicketsUpdatedEvent) {
    myTickets.value = event.my_tickets
  }

  function reset() {
    code.value = ''
    hostId.value = null
    status.value = 'lobby'
    board.value = { picks: [], count: 0, finished: false }
    myTickets.value = []
    myStruck.value = new Set()
    players.value = []
    prizes.value = {}
    prizeProgress.value = {}
    channelConnected.value = false
    hydrated.value = false
    autoStrikeEnabled.value = false
  }

  return {
    code, name, hostId, status, settings, board, myTickets, myStruck,
    players, prizes, prizeProgress, nextPickAt, channelConnected, hydrated,
    autoStrikeEnabled, hydrate, onPick, onStatusChange, onPrizeClaimed, onBogey,
    onPlayerJoined, onPlayerLeft, onStrikeConfirmed, onTicketCountUpdated,
    onMyTicketsUpdated, reset,
  }
})
```

- [ ] **Step 2: TypeScript check**

```bash
cd assets && npx tsc --noEmit 2>&1 | head -30
```

Expected: errors only in pages/composables not yet updated.

- [ ] **Step 3: Commit**

```bash
cd ..
git add assets/js/stores/game.ts
git commit -m "feat: update game store for multi-ticket (myTickets, onTicketCountUpdated)"
```

---

## Task 16: composables/useChannel.ts

**Files:**
- Modify: `assets/js/composables/useChannel.ts`

- [ ] **Step 1: Update claim signature and add new event listeners**

In `useChannel.ts`:

1. Change the `claim` function:
```typescript
function claim(prize: string, ticketId: string) {
  channel?.push('claim', { prize, ticket_id: ticketId })
}
```

2. Add inside `connect()`, after the existing `channel.on('player_left', ...)` listener:
```typescript
channel.on('ticket_count_updated', (event: TicketCountUpdatedEvent) => {
  gameStore.onTicketCountUpdated(event)
})

channel.on('my_tickets_updated', (event: MyTicketsUpdatedEvent) => {
  gameStore.onMyTicketsUpdated(event)
})
```

3. Add the new types to the import:
```typescript
import type {
  NumberPickedEvent, GameStatusEvent, PrizeClaimedEvent, ClaimRejectionEvent,
  StrikeResultEvent, BogeyEvent, ChatEvent, ReactionEvent,
  PlayerJoinedEvent, PlayerLeftEvent, PresenceDiff, GameJoinReply,
  TicketCountUpdatedEvent, MyTicketsUpdatedEvent,
} from '@/types/channel'
```

4. Update the return type of `claim` in the return statement (the function ref is updated).

- [ ] **Step 2: TypeScript check**

```bash
cd assets && npx tsc --noEmit 2>&1 | head -30
```

Expected: errors only in GamePlay.vue (not yet updated).

- [ ] **Step 3: Commit**

```bash
cd ..
git add assets/js/composables/useChannel.ts
git commit -m "feat: update useChannel for multi-ticket (claim with ticketId, new events)"
```

---

## Task 17: pages/NewGame.vue — default_ticket_count Field

**Files:**
- Modify: `assets/js/pages/NewGame.vue`

- [ ] **Step 1: Add the ref and update create()**

In the `<script setup>` section, add after `const bogeyLimit = ref(3)`:
```typescript
const defaultTicketCount = ref(1)
```

In `create()`, add `default_ticket_count` to the API call:
```typescript
const { code } = await api.games.create({
  name: name.value || 'Tambola',
  interval: interval.value,
  bogey_limit: bogeyLimit.value,
  enabled_prizes: enabledPrizes.value,
  visibility: visibility.value,
  join_secret: visibility.value === 'private' ? joinSecret.value : undefined,
  default_ticket_count: defaultTicketCount.value,
})
```

- [ ] **Step 2: Add the UI control** — insert a Card after the Bogey limit Card in the template

```html
<Card>
  <h3 class="mb-3 text-sm font-semibold">Tickets per player</h3>
  <div class="flex gap-2">
    <Button
      v-for="n in [1, 2, 3, 4, 5, 6]"
      :key="n"
      type="button"
      :variant="defaultTicketCount === n ? 'primary' : 'secondary'"
      @click="defaultTicketCount = n"
    >{{ n }}</Button>
  </div>
</Card>
```

- [ ] **Step 3: TypeScript check**

```bash
cd assets && npx tsc --noEmit 2>&1 | head -20
```

Expected: errors only in GamePlay.vue.

- [ ] **Step 4: Commit**

```bash
cd ..
git add assets/js/pages/NewGame.vue
git commit -m "feat: add default_ticket_count selector to NewGame form"
```

---

## Task 18: pages/HostDashboard.vue — Per-Player Ticket Count Controls

**Files:**
- Modify: `assets/js/pages/HostDashboard.vue`

- [ ] **Step 1: Add the ticket count update function and import api**

In the `<script setup>` section, `api` is already imported. Add a function to update ticket count:

```typescript
async function setTicketCount(userId: string, newCount: number) {
  if (newCount < 1 || newCount > 6) return
  try {
    await api.games.setTicketCount(code, userId, newCount)
  } catch (e: any) {
    actionError.value = e.message ?? 'Failed to update tickets'
  }
}
```

- [ ] **Step 2: Update the player chip in the lobby section**

Replace the existing player chip `<div v-for="p in gameStore.players" ...>` with:

```html
<div
  v-for="p in gameStore.players"
  :key="p.user_id"
  class="flex items-center gap-2 rounded-full bg-[--bg] border border-[--border] px-3 py-2 text-sm shadow-sm animate-scale-in"
>
  <Avatar :name="p.name" :user-id="p.user_id" size="sm" class="ring-2 ring-indigo-500/30" />
  <span class="font-medium">{{ p.name }}</span>
  <div class="flex items-center gap-1 ml-1 border-l border-[--border] pl-2">
    <button
      @click="setTicketCount(p.user_id, (p.ticket_count ?? 1) - 1)"
      :disabled="(p.ticket_count ?? 1) <= 1"
      class="w-5 h-5 flex items-center justify-center rounded-full bg-[--elevated] text-[--text-secondary] hover:bg-[--surface] disabled:opacity-30 disabled:cursor-not-allowed text-xs font-bold transition-colors"
    >−</button>
    <span class="font-mono font-bold text-indigo-400 w-4 text-center text-xs">{{ p.ticket_count ?? 1 }}</span>
    <button
      @click="setTicketCount(p.user_id, (p.ticket_count ?? 1) + 1)"
      :disabled="(p.ticket_count ?? 1) >= 6"
      class="w-5 h-5 flex items-center justify-center rounded-full bg-[--elevated] text-[--text-secondary] hover:bg-[--surface] disabled:opacity-30 disabled:cursor-not-allowed text-xs font-bold transition-colors"
    >+</button>
  </div>
</div>
```

- [ ] **Step 3: TypeScript check**

```bash
cd assets && npx tsc --noEmit 2>&1 | head -20
```

Expected: errors only in GamePlay.vue.

- [ ] **Step 4: Commit**

```bash
cd ..
git add assets/js/pages/HostDashboard.vue
git commit -m "feat: add per-player ticket count controls to HostDashboard lobby"
```

---

## Task 19: pages/GamePlay.vue — Multiple TicketGrid Instances

**Files:**
- Modify: `assets/js/pages/GamePlay.vue`

- [ ] **Step 1: Update script section**

Remove `const ticketRef = ref<InstanceType<typeof TicketGrid> | null>(null)` and replace with:
```typescript
const ticketRefs = ref<Array<InstanceType<typeof TicketGrid>>>([])
```

Update the `$onAction` subscription — replace the `onStrikeConfirmed` handler:
```typescript
if (name === 'onStrikeConfirmed') {
  ticketRefs.value.forEach(ref => ref?.onStrikeResult(args[0].number, args[0].result))
}
```

Update the `onPick` handler to check across all tickets:
```typescript
if (name === 'onPick') {
  const event = args[0] as any
  after(() => {
    const isOnTicket = gameStore.myTickets.some(t => t.numbers.includes(event.number))
    const interval = gameStore.settings.interval
    const durationMs = Math.max(1000, Math.min(3000, (interval - 1) * 1000))
    numberCallRef.value?.show(event.number, isOnTicket, durationMs)
  })
}
```

Update `myPrizesWon` — no change needed (still based on `winner_id`).

- [ ] **Step 2: Update lobby ticket display**

Replace the single `<TicketGrid v-if="gameStore.myTicket" ...>` block in the lobby section with:

```html
<div class="w-full flex flex-col gap-4">
  <h3 class="font-bold text-center text-[--text-secondary] uppercase tracking-wider text-sm">
    Your {{ gameStore.myTickets.length === 1 ? 'Ticket' : 'Tickets' }} for this Game
  </h3>
  <div
    v-for="(ticket, index) in gameStore.myTickets"
    :key="ticket.id"
    class="relative bg-[--surface]/40 backdrop-blur-xl p-4 md:p-6 rounded-3xl border border-[--border] shadow-[0_8px_40px_rgb(0,0,0,0.04)]"
  >
    <span v-if="gameStore.myTickets.length > 1" class="text-xs font-bold text-[--text-secondary] uppercase tracking-wider mb-2 block">
      Ticket {{ index + 1 }}
    </span>
    <TicketGrid
      :ticket="ticket"
      :struck="gameStore.myStruck"
      :picked-numbers="gameStore.board.picks"
      :interactive="false"
    />
  </div>
</div>
```

- [ ] **Step 3: Update running/paused ticket section**

Replace the single ticket card (the `<!-- Ticket -->` comment section) with a multi-ticket layout. Replace from `<!-- Ticket -->` to the closing `</div>` of that card:

```html
<!-- Tickets -->
<div
  v-for="(ticket, index) in gameStore.myTickets"
  :key="ticket.id"
  class="relative bg-[--surface]/40 backdrop-blur-xl p-4 md:p-6 rounded-3xl border border-[--border] shadow-[0_8px_40px_rgb(0,0,0,0.04)] flex flex-col gap-4"
>
  <div class="flex items-center justify-between">
    <span class="text-sm font-bold text-[--text-secondary] uppercase tracking-wider">
      {{ gameStore.myTickets.length > 1 ? `Ticket ${index + 1}` : 'Your Ticket' }}
    </span>
    <label v-if="index === 0" class="flex items-center gap-2 cursor-pointer group">
      <span class="text-xs font-bold text-[--text-secondary] uppercase tracking-wider group-hover:text-indigo-500 transition-colors">Auto Strike</span>
      <div class="relative">
        <input type="checkbox" v-model="gameStore.autoStrikeEnabled" class="sr-only peer" />
        <div class="w-9 h-5 bg-[--border] peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-indigo-500"></div>
      </div>
    </label>
  </div>
  <TicketGrid
    :ref="(el) => { if (el) ticketRefs[index] = el as InstanceType<typeof TicketGrid> }"
    :ticket="ticket"
    :struck="gameStore.myStruck"
    :picked-numbers="gameStore.board.picks"
    :interactive="gameStore.status === 'running'"
    @strike="strike"
  />
  <!-- Per-ticket prize claim buttons -->
  <div class="flex flex-wrap gap-2 pt-2 border-t border-[--border]">
    <button
      v-for="(status, prize) in gameStore.prizes"
      :key="prize"
      @click="!status.claimed && claim(prize, ticket.id)"
      :disabled="status.claimed"
      class="flex-1 min-w-[100px] text-center px-3 py-2 rounded-xl border transition-all duration-200 text-xs font-bold"
      :class="[
        status.claimed
          ? 'border-yellow-500/20 bg-yellow-500/5 text-yellow-600/50 dark:text-yellow-400/50 cursor-not-allowed'
          : myPrizesWon.includes(prize)
          ? 'border-green-500 bg-green-500/10 text-green-600 dark:text-green-400'
          : 'border-[--border] bg-[--surface] text-[--text-primary] hover:border-indigo-500 hover:-translate-y-0.5'
      ]"
    >
      <span class="capitalize">{{ prize.replace(/_/g, ' ') }}</span>
      <span v-if="status.claimed" class="block text-[10px] opacity-70">
        {{ myPrizesWon.includes(prize) ? 'You Won!' : 'Claimed' }}
      </span>
      <span v-else-if="gameStore.prizeProgress[ticket.id]?.[prize]" class="block text-[10px] opacity-60 font-mono">
        {{ gameStore.prizeProgress[ticket.id][prize].struck }}/{{ gameStore.prizeProgress[ticket.id][prize].required }}
      </span>
    </button>
  </div>
</div>
```

- [ ] **Step 4: Remove the old right-column prizes card** (it was `<!-- Prizes -->` in the right column). Since prizes are now per-ticket, remove the standalone prize card from the right column. The right column can be removed or repurposed for another purpose. Remove the entire `<!-- Right Column -->` section that contains the prizes `Card`.

- [ ] **Step 5: TypeScript check**

```bash
cd assets && npx tsc --noEmit
```

Expected: 0 errors.

- [ ] **Step 6: Run frontend tests**

```bash
cd assets && npx vitest run
```

Expected: all tests pass (or pre-existing failures only).

- [ ] **Step 7: Commit**

```bash
cd ..
git add assets/js/pages/GamePlay.vue
git commit -m "feat: update GamePlay for multi-ticket (N TicketGrids, per-ticket claim buttons)"
```

---

## Task 20: End-to-End Smoke Test + Final Check

- [ ] **Step 1: Run full backend test suite**

```bash
mix test
```

Expected: all tests pass.

- [ ] **Step 2: Start the dev server and verify manually**

```bash
mix phx.server
```

Open http://localhost:5173.

Verify:
- New Game form shows "Tickets per player" control (1–6)
- Create game with 2 tickets per player
- Join as a second user — should see 2 ticket grids in lobby
- As host: player chip shows ticket count with +/– controls
- Change player's count to 3 — player immediately sees 3 tickets
- Start game — game runs with correct ticket count
- Each ticket has its own claim buttons with progress indicators

- [ ] **Step 3: Final commit**

```bash
git add -p  # stage any remaining changes
git commit -m "chore: final multi-ticket integration cleanup"
```

---

## Self-Review Against Spec

| Spec requirement | Task(s) |
|---|---|
| Game-wide `default_ticket_count` set at creation | Tasks 10, 11, 17 |
| Per-player override in lobby (1–6 cap) | Tasks 5, 11, 12, 18 |
| Strip of 6 tickets, 1–90 once | Task 3 |
| Each ticket has UUID | Task 3 |
| `state.tickets = %{ticket_id => Ticket}` | Tasks 4–9 |
| `state.ticket_owners`, `state.player_ticket_counts` | Tasks 4–9 |
| DB migration `ticket → tickets array` | Tasks 1, 2 |
| `set_ticket_count` server handler | Task 5 |
| `start_game` trims inactive tickets | Task 6 |
| `strike_out` checks across all active tickets | Task 7 |
| `claim` takes `ticket_id` | Tasks 8, 11, 12, 16 |
| `prize_progress` keyed by `ticket_id` | Task 9 |
| `ticket_count_updated` + `player_tickets_updated` broadcast | Tasks 5, 12 |
| Channel join reply sends `my_tickets` | Task 12 |
| TypeScript types updated | Task 13 |
| `api.games.setTicketCount` | Task 14 |
| Store updated for `myTickets`, new events | Task 15 |
| `useChannel.claim(prize, ticketId)` | Task 16 |
| NewGame form: tickets-per-player control | Task 17 |
| HostDashboard: per-player +/– controls | Task 18 |
| GamePlay: N TicketGrids + per-ticket claim | Task 19 |

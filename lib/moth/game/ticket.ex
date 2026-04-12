defmodule Moth.Game.Ticket do
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
    # Phase 1: Build a valid 6×9 count matrix.
    # row sums = 15 (15 numbers per ticket)
    # col c sum = col_sizes[c] (all numbers in that column distributed)
    # each cell in 0..3 (Tambola column constraint)
    #
    # Algorithm: fill one ticket at a time. For each ticket, compute per-column
    # lower bounds (must take at least this many to leave a feasible remainder for
    # future tickets) and upper bounds (at most 3 or column remainder). Then
    # randomly fill up to 15. This is provably deadlock-free: lower ≤ upper always
    # holds, and 15 is always reachable given the bounds.
    col_sizes = for col <- 0..8 do
      {low, high} = column_range(col)
      high - low + 1
    end

    {count_matrix, _} =
      Enum.reduce(1..6, {[], col_sizes}, fn _, {rows, col_remaining} ->
        r = 6 - length(rows)
        lower = Enum.map(col_remaining, fn rem ->
          # Feasibility floor: must take enough so future tickets (max 3 each) can absorb the rest
          feasibility = max(0, rem - 3 * (r - 1))
          # Every column with remaining numbers must contribute at least 1
          if rem > 0, do: max(1, feasibility), else: 0
        end)
        upper = Enum.map(col_remaining, &min(3, &1))
        counts = random_bounded_sum(lower, upper, 15)
        new_remaining = Enum.zip(col_remaining, counts) |> Enum.map(fn {a, b} -> a - b end)
        {rows ++ [counts], new_remaining}
      end)

    # Phase 2: Shuffle each column's numbers, then slice according to count_matrix.
    column_pools =
      for col <- 0..8 do
        {low, high} = column_range(col)
        Enum.to_list(low..high) |> Enum.shuffle()
      end

    {tickets, _} =
      Enum.reduce(count_matrix, {[], column_pools}, fn ticket_counts, {tickets_acc, pools} ->
        {col_numbers, new_pools} =
          Enum.zip(ticket_counts, pools)
          |> Enum.reduce({[], []}, fn {count, pool}, {nums, new_ps} ->
            {nums ++ [Enum.take(pool, count) |> Enum.sort()], new_ps ++ [Enum.drop(pool, count)]}
          end)

        col_counts = Enum.map(col_numbers, &length/1)
        rows = assign_to_rows(col_numbers, col_counts)
        numbers = col_numbers |> List.flatten() |> MapSet.new()
        ticket = %__MODULE__{id: Ecto.UUID.generate(), rows: rows, numbers: numbers}
        {tickets_acc ++ [ticket], new_pools}
      end)

    tickets
  end

  @doc "Converts a ticket to a serializable map."
  def to_map(%__MODULE__{id: id, rows: rows, numbers: numbers}) do
    %{"id" => id, "rows" => rows, "numbers" => numbers |> MapSet.to_list() |> Enum.sort()}
  end

  @doc "Restores a ticket from a map."
  def from_map(%{"id" => id, "rows" => rows, "numbers" => numbers}) do
    %__MODULE__{id: id, rows: rows, numbers: MapSet.new(numbers)}
  end

  def from_map(%{"rows" => rows, "numbers" => numbers}) do
    %__MODULE__{rows: rows, numbers: MapSet.new(numbers)}
  end

  # ── Strip internals ───────────────────────────────────────────────────────────

  # Randomly build a count vector in [lower[c], upper[c]] summing to target.
  # Starts at lower bounds, then distributes the deficit randomly.
  # Provably always succeeds: sum(lower) ≤ target ≤ sum(upper) by construction.
  defp random_bounded_sum(lower, upper, target) do
    deficit = target - Enum.sum(lower)

    Enum.reduce(0..(deficit - 1)//1, lower, fn _, counts ->
      eligible =
        counts
        |> Enum.zip(upper)
        |> Enum.with_index()
        |> Enum.filter(fn {{c, u}, _} -> c < u end)
        |> Enum.map(fn {_, i} -> i end)

      idx = Enum.random(eligible)
      List.update_at(counts, idx, &(&1 + 1))
    end)
  end

  # Deterministic greedy row assignment: no random retries.
  # For each row (0..2), greedily picks the 5 columns with the highest remaining
  # capacity, then decrements those columns' remaining counts.
  # Guaranteed to produce [5,5,5] because valid col_counts (sum=15, each ≤ 3)
  # always have ≥ 5 non-zero columns at every step.
  defp assign_to_rows(col_numbers, col_counts) do
    {per_col_rows, _} =
      Enum.reduce(0..2, {List.duplicate([], 9), col_counts}, fn row, {per_col, remaining} ->
        chosen =
          remaining
          |> Enum.with_index()
          |> Enum.filter(fn {r, _} -> r > 0 end)
          |> Enum.sort_by(fn {r, i} -> {-r, i} end)
          |> Enum.take(5)
          |> Enum.map(fn {_, i} -> i end)

        new_per_col =
          per_col
          |> Enum.with_index()
          |> Enum.map(fn {rows, col} ->
            if col in chosen, do: rows ++ [row], else: rows
          end)

        new_remaining =
          remaining
          |> Enum.with_index()
          |> Enum.map(fn {r, col} -> if col in chosen, do: r - 1, else: r end)

        {new_per_col, new_remaining}
      end)

    build_rows(col_numbers, per_col_rows)
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

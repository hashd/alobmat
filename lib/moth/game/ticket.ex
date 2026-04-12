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

  @doc "Generates a valid Tambola ticket."
  def generate do
    # Step 1: For each column, pick random numbers from the column range
    column_pools =
      for col <- 0..8 do
        {low, high} = column_range(col)
        Enum.to_list(low..high) |> Enum.shuffle()
      end

    # Step 2: Determine how many numbers each column contributes (1-3)
    col_counts = distribute_numbers(column_pools)

    # Step 3: Pick that many numbers from each column pool, sort them
    col_numbers =
      Enum.zip(column_pools, col_counts)
      |> Enum.map(fn {pool, count} ->
        pool |> Enum.take(count) |> Enum.sort()
      end)

    # Step 4: Assign numbers to rows, ensuring 5 per row
    rows = assign_to_rows(col_numbers, col_counts)

    numbers =
      rows
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %__MODULE__{rows: rows, numbers: numbers}
  end

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

  def from_map(%{"rows" => rows, "numbers" => numbers}) do
    %__MODULE__{rows: rows, numbers: MapSet.new(numbers)}
  end

  # ── Strip generation ─────────────────────────────────────────────────────────

  defp do_generate_strip do
    column_pools =
      for col <- 0..8 do
        {low, high} = column_range(col)
        Enum.to_list(low..high) |> Enum.shuffle()
      end

    col_assignments =
      Enum.map(column_pools, fn pool ->
        counts = fill_counts(List.duplicate(0, 6), length(pool), 3) |> Enum.shuffle()
        split_by_counts(pool, counts)
      end)

    tickets_data =
      for t <- 0..5 do
        col_nums = Enum.map(col_assignments, fn slots -> Enum.at(slots, t) end)
        col_counts = Enum.map(col_nums, &length/1)
        {col_nums, col_counts}
      end

    tickets =
      Enum.map(tickets_data, fn {col_nums, col_counts} ->
        rows = assign_to_rows(col_nums, col_counts)
        numbers = rows |> List.flatten() |> Enum.reject(&is_nil/1) |> MapSet.new()
        %__MODULE__{id: Ecto.UUID.generate(), rows: rows, numbers: numbers}
      end)

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

  defp split_by_counts(pool, counts) do
    {_, result} =
      Enum.reduce(counts, {pool, []}, fn count, {remaining, acc} ->
        {taken, rest} = Enum.split(remaining, count)
        {rest, acc ++ [Enum.sort(taken)]}
      end)

    result
  end

  # ── Single-ticket helpers ────────────────────────────────────────────────────

  defp distribute_numbers(column_pools) do
    pool_sizes = Enum.map(column_pools, &length/1)
    base = List.duplicate(1, 9)
    remaining = 6
    add_numbers(base, remaining, pool_sizes)
  end

  defp add_numbers(counts, 0, _pools), do: counts

  defp add_numbers(counts, remaining, pool_sizes) do
    eligible =
      counts
      |> Enum.with_index()
      |> Enum.filter(fn {count, idx} ->
        count < 3 and count < Enum.at(pool_sizes, idx)
      end)
      |> Enum.map(fn {_count, idx} -> idx end)

    idx = Enum.random(eligible)
    counts = List.update_at(counts, idx, &(&1 + 1))
    add_numbers(counts, remaining - 1, pool_sizes)
  end

  # ── Row assignment ────────────────────────────────────────────────────────────

  # Deterministic greedy row assignment: no random retries.
  # For each row (0..2), greedily picks the 5 columns with the highest remaining
  # capacity, then decrements those columns' remaining counts.
  # Guaranteed to produce [5,5,5] because valid col_counts (sum=15, each ≤ 3)
  # always have ≥ 5 non-zero columns at every step.
  defp assign_to_rows(col_numbers, col_counts) do
    {per_col_rows, _} =
      Enum.reduce(0..2, {List.duplicate([], 9), col_counts}, fn row, {per_col, remaining} ->
        # Pick 5 cols with highest remaining; break ties by column index (stable)
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

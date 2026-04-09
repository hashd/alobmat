defmodule Moth.Game.Ticket do
  @moduledoc """
  Pure functions for generating valid Tambola tickets.

  Rules:
  - 3 rows x 9 columns
  - Each row has exactly 5 numbers and 4 blanks
  - Column 0: 1-9, Column 1: 10-19, ..., Column 8: 80-90
  - Numbers within a column are sorted top to bottom
  - 15 unique numbers total
  """

  defstruct rows: [], numbers: MapSet.new()

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

  @doc "Converts a ticket to a serializable map."
  def to_map(%__MODULE__{rows: rows, numbers: numbers}) do
    %{"rows" => rows, "numbers" => MapSet.to_list(numbers)}
  end

  @doc "Restores a ticket from a map."
  def from_map(%{"rows" => rows, "numbers" => numbers}) do
    %__MODULE__{rows: rows, numbers: MapSet.new(numbers)}
  end

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

  defp assign_to_rows(col_numbers, col_counts) do
    row_assignments =
      col_counts
      |> Enum.with_index()
      |> Enum.map(fn {count, _col} ->
        Enum.take_random(0..2 |> Enum.to_list(), count)
      end)

    row_totals = Enum.reduce(row_assignments, [0, 0, 0], fn rows, acc ->
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

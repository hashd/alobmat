defmodule Mocha.Game.Prize do
  @moduledoc "Pure functions for validating Tambola prize claims."

  alias Mocha.Game.Ticket

  @prizes [:early_five, :top_line, :middle_line, :bottom_line, :full_house]

  def all_prizes, do: @prizes

  @doc """
  Checks whether a prize claim is valid.
  Returns :valid or :invalid.
  """
  def check_claim(:top_line, %Ticket{rows: [row | _]}, picked) do
    row_filled?(row, picked)
  end

  def check_claim(:middle_line, %Ticket{rows: [_, row, _]}, picked) do
    row_filled?(row, picked)
  end

  def check_claim(:bottom_line, %Ticket{rows: [_, _, row]}, picked) do
    row_filled?(row, picked)
  end

  def check_claim(:early_five, %Ticket{numbers: numbers}, picked) do
    matched = MapSet.intersection(numbers, picked) |> MapSet.size()
    if matched >= 5, do: :valid, else: :invalid
  end

  def check_claim(:full_house, %Ticket{numbers: numbers}, picked) do
    if MapSet.subset?(numbers, picked), do: :valid, else: :invalid
  end

  defp row_filled?(row, picked) do
    row_numbers =
      row
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    if MapSet.subset?(row_numbers, picked), do: :valid, else: :invalid
  end
end

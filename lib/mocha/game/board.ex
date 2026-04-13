defmodule Mocha.Game.Board do
  @moduledoc "Pure functions for the Tambola number board (1-90)."

  defstruct bag: [], picks: [], count: 0

  @doc "Creates a new board with shuffled numbers 1-90."
  def new(seed \\ nil) do
    bag =
      if seed do
        # Deterministic shuffle for testing
        :rand.seed(:exsss, {seed, seed, seed})
        1..90 |> Enum.to_list() |> Enum.shuffle()
      else
        1..90 |> Enum.to_list() |> Enum.shuffle()
      end

    %__MODULE__{bag: bag, picks: [], count: 0}
  end

  @doc "Picks the next number from the bag. Returns {number, updated_board} or {:finished, board}."
  def pick(%__MODULE__{bag: []} = board), do: {:finished, board}

  def pick(%__MODULE__{bag: [number | rest], picks: picks, count: count}) do
    {number, %__MODULE__{bag: rest, picks: [number | picks], count: count + 1}}
  end

  @doc "Returns true if all 90 numbers have been picked."
  def finished?(%__MODULE__{count: 90}), do: true
  def finished?(%__MODULE__{}), do: false

  @doc "Returns the current state as a serializable map."
  def to_map(%__MODULE__{} = board) do
    %{picks: board.picks, count: board.count, finished: finished?(board)}
  end

  @doc "Restores a board from a snapshot map."
  def from_snapshot(%{"picks" => picks, "count" => count}) do
    picked_set = MapSet.new(picks)
    remaining = Enum.reject(1..90, &MapSet.member?(picked_set, &1)) |> Enum.shuffle()
    %__MODULE__{bag: remaining, picks: picks, count: count}
  end
end

defmodule Moth.Housie.Board do
  defstruct(
    bag: 1..90, 
    picks: [], 
    count: 0
  )

  alias Moth.Housie.Board

  def start_link do
    Agent.start_link(fn -> %Board{} end)
  end

  def bag(board), do: Agent.get(board, fn s -> s.bag end)
  def picks(board), do: Agent.get(board, fn s -> s.picks end)
  def count(board), do: Agent.get(board, fn s -> s.count end)
  def state(board), do: Agent.get(board, fn s -> %{ picks: s.picks, running: s.count != 90 && s.count != 0 } end)
  def has_finished?(board), do: count(board) == 90

  def pick(board) do
    [pick | rest] = bag(board) |> Enum.shuffle
    numbers = picks(board)
    n_picks = count(board)
    Agent.update(board, fn s -> 
      s 
      |> Map.put(:bag, rest)
      |> Map.put(:picks, [ pick | numbers ])
      |> Map.put(:count, n_picks + 1)
    end)
    pick
  end
end
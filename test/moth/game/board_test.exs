defmodule Moth.Game.BoardTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Moth.Game.Board

  describe "new/0" do
    test "creates a board with 90 numbers in the bag" do
      board = Board.new()
      assert length(board.bag) == 90
      assert board.picks == []
      assert board.count == 0
    end

    test "bag contains numbers 1 through 90" do
      board = Board.new()
      assert Enum.sort(board.bag) == Enum.to_list(1..90)
    end
  end

  describe "pick/1" do
    test "removes one number from bag and adds to picks" do
      board = Board.new()
      {number, board} = Board.pick(board)
      assert is_integer(number)
      assert number >= 1 and number <= 90
      assert length(board.bag) == 89
      assert board.picks == [number]
      assert board.count == 1
    end

    test "never returns the same number twice" do
      board = Board.new()

      {_numbers, final_board} =
        Enum.reduce(1..90, {[], board}, fn _, {nums, b} ->
          {n, b} = Board.pick(b)
          {[n | nums], b}
        end)

      assert final_board.count == 90
      assert length(Enum.uniq(final_board.picks)) == 90
    end

    test "returns {:finished, board} when bag is empty" do
      board = Board.new()

      board =
        Enum.reduce(1..90, board, fn _, b ->
          {_n, b} = Board.pick(b)
          b
        end)

      assert Board.pick(board) == {:finished, board}
    end
  end

  describe "finished?/1" do
    test "returns false for new board" do
      refute Board.finished?(Board.new())
    end

    test "returns true after 90 picks" do
      board =
        Enum.reduce(1..90, Board.new(), fn _, b ->
          {_n, b} = Board.pick(b)
          b
        end)

      assert Board.finished?(board)
    end
  end

  describe "property: pick exhausts 1..90" do
    property "picking all 90 numbers yields exactly 1..90" do
      check all(seed <- integer()) do
        board = Board.new(seed)

        {_board, all_picks} =
          Enum.reduce(1..90, {board, []}, fn _, {b, picks} ->
            {n, b} = Board.pick(b)
            {b, [n | picks]}
          end)

        assert Enum.sort(all_picks) == Enum.to_list(1..90)
      end
    end
  end
end

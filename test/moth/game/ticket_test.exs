defmodule Moth.Game.TicketTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Moth.Game.Ticket

  describe "generate/0" do
    test "returns a ticket with 3 rows" do
      ticket = Ticket.generate()
      assert length(ticket.rows) == 3
    end

    test "each row has 9 columns" do
      ticket = Ticket.generate()
      Enum.each(ticket.rows, fn row -> assert length(row) == 9 end)
    end

    test "each row has exactly 5 numbers and 4 nils" do
      ticket = Ticket.generate()
      Enum.each(ticket.rows, fn row ->
        numbers = Enum.reject(row, &is_nil/1)
        assert length(numbers) == 5
      end)
    end

    test "ticket has exactly 15 unique numbers" do
      ticket = Ticket.generate()
      assert MapSet.size(ticket.numbers) == 15
    end

    test "numbers fall in correct column ranges" do
      ticket = Ticket.generate()
      Enum.each(ticket.rows, fn row ->
        row
        |> Enum.with_index()
        |> Enum.each(fn {val, col} ->
          if val do
            {low, high} = Ticket.column_range(col)
            assert val >= low and val <= high,
                   "#{val} not in range #{low}..#{high} for column #{col}"
          end
        end)
      end)
    end

    test "numbers within a column are sorted top to bottom" do
      ticket = Ticket.generate()
      for col <- 0..8 do
        col_values =
          ticket.rows
          |> Enum.map(&Enum.at(&1, col))
          |> Enum.reject(&is_nil/1)
        assert col_values == Enum.sort(col_values),
               "Column #{col} not sorted: #{inspect(col_values)}"
      end
    end
  end

  describe "property: generate always produces valid tickets" do
    property "all generated tickets satisfy Tambola rules" do
      check all _ <- constant(:ok), max_runs: 200 do
        ticket = Ticket.generate()
        assert length(ticket.rows) == 3
        Enum.each(ticket.rows, fn row -> assert length(row) == 9 end)
        Enum.each(ticket.rows, fn row ->
          assert length(Enum.reject(row, &is_nil/1)) == 5
        end)
        assert MapSet.size(ticket.numbers) == 15
        Enum.each(ticket.rows, fn row ->
          row
          |> Enum.with_index()
          |> Enum.each(fn {val, col} ->
            if val do
              {low, high} = Ticket.column_range(col)
              assert val >= low and val <= high
            end
          end)
        end)
        for col <- 0..8 do
          col_values =
            ticket.rows
            |> Enum.map(&Enum.at(&1, col))
            |> Enum.reject(&is_nil/1)
          assert col_values == Enum.sort(col_values)
        end
      end
    end
  end

  describe "column_range/1" do
    test "column 0 is 1-9" do
      assert Ticket.column_range(0) == {1, 9}
    end

    test "column 8 is 80-90" do
      assert Ticket.column_range(8) == {80, 90}
    end
  end
end

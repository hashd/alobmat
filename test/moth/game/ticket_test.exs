defmodule Moth.Game.TicketTest do
  use ExUnit.Case, async: true

  alias Moth.Game.Ticket

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
          col_nums =
            Enum.flat_map(ticket.rows, fn row -> [Enum.at(row, col)] end)
            |> Enum.reject(&is_nil/1)
          Enum.each(col_nums, fn n ->
            assert n >= low and n <= high,
                   "Number #{n} in col #{col} is outside range #{low}-#{high}"
          end)
        end
      end)
    end

    test "is valid across 5 runs" do
      for _ <- 1..5 do
        strip = Ticket.generate_strip()
        all_numbers = strip |> Enum.flat_map(fn t -> MapSet.to_list(t.numbers) end) |> Enum.sort()
        assert all_numbers == Enum.to_list(1..90)
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

  describe "to_map/1 and from_map/1" do
    test "to_map includes id" do
      [ticket | _] = Ticket.generate_strip()
      map = Ticket.to_map(ticket)
      assert Map.has_key?(map, "id")
      assert map["id"] == ticket.id
    end

    test "round-trips id through to_map/from_map" do
      [ticket | _] = Ticket.generate_strip()
      map = Ticket.to_map(ticket)
      restored = Ticket.from_map(map)
      assert restored.id == ticket.id
    end
  end
end

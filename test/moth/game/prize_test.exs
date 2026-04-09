defmodule Moth.Game.PrizeTest do
  use ExUnit.Case, async: true

  alias Moth.Game.{Prize, Ticket}

  defp make_ticket(rows) do
    numbers =
      rows
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %Ticket{rows: rows, numbers: numbers}
  end

  defp sample_ticket do
    make_ticket([
      [4, nil, nil, 23, nil, 50, nil, 71, nil],
      [nil, 12, nil, nil, 40, nil, 62, nil, 85],
      [nil, nil, 30, nil, nil, 55, nil, 78, 90]
    ])
  end

  describe "check_claim/3 - top_line" do
    test "valid when all row 1 numbers are picked" do
      picked = MapSet.new([4, 23, 50, 71, 10, 20, 30])
      assert Prize.check_claim(:top_line, sample_ticket(), picked) == :valid
    end

    test "invalid when row 1 is incomplete" do
      picked = MapSet.new([4, 23, 50])
      assert Prize.check_claim(:top_line, sample_ticket(), picked) == :invalid
    end
  end

  describe "check_claim/3 - middle_line" do
    test "valid when all row 2 numbers are picked" do
      picked = MapSet.new([12, 40, 62, 85, 1, 2])
      assert Prize.check_claim(:middle_line, sample_ticket(), picked) == :valid
    end
  end

  describe "check_claim/3 - bottom_line" do
    test "valid when all row 3 numbers are picked" do
      picked = MapSet.new([30, 55, 78, 90, 1])
      assert Prize.check_claim(:bottom_line, sample_ticket(), picked) == :valid
    end
  end

  describe "check_claim/3 - early_five" do
    test "valid when any 5 ticket numbers are picked" do
      picked = MapSet.new([4, 12, 30, 50, 62])
      assert Prize.check_claim(:early_five, sample_ticket(), picked) == :valid
    end

    test "invalid when fewer than 5 ticket numbers picked" do
      picked = MapSet.new([4, 12, 30, 50])
      assert Prize.check_claim(:early_five, sample_ticket(), picked) == :invalid
    end
  end

  describe "check_claim/3 - full_house" do
    test "valid when all 15 numbers are picked" do
      picked = MapSet.new([4, 23, 50, 71, 12, 40, 62, 85, 30, 55, 78, 90])
      assert Prize.check_claim(:full_house, sample_ticket(), picked) == :valid
    end

    test "invalid when not all numbers picked" do
      picked = MapSet.new([4, 23, 50, 71, 12, 40, 62, 85, 30, 55, 78])
      assert Prize.check_claim(:full_house, sample_ticket(), picked) == :invalid
    end
  end

  describe "all_prizes/0" do
    test "returns all 5 prize types" do
      assert Prize.all_prizes() == [:early_five, :top_line, :middle_line, :bottom_line, :full_house]
    end
  end
end

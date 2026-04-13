defmodule Mocha.Game.CodeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Mocha.Game.Code

  describe "generate/0" do
    test "returns a string matching WORD-NNN format" do
      code = Code.generate()
      assert Regex.match?(~r/^[A-Z]+-\d{3}$/, code)
    end

    test "generates different codes on successive calls" do
      codes = for _ <- 1..20, do: Code.generate()
      assert length(Enum.uniq(codes)) == 20
    end
  end

  describe "generate/1 with exclusion set" do
    test "avoids codes in the exclusion set" do
      first = Code.generate()
      excluded = MapSet.new([first])
      codes = for _ <- 1..50, do: Code.generate(excluded)
      refute first in codes
    end
  end

  describe "property: codes always match format" do
    property "all generated codes match WORD-NNN" do
      check all(_ <- constant(:ok), max_runs: 100) do
        code = Code.generate()
        assert Regex.match?(~r/^[A-Z]+-\d{3}$/, code)
      end
    end
  end
end

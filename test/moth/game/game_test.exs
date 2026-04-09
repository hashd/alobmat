defmodule Moth.Game.GameTest do
  use Moth.DataCase, async: false

  alias Moth.Game

  import Moth.AuthFixtures
  import Moth.GameFixtures

  describe "create_game/2" do
    test "creates a game and starts a server" do
      host = user_fixture()
      assert {:ok, code} = Game.create_game(host.id, %{name: "My Game"})
      assert is_binary(code)
      assert {:ok, state} = Game.game_state(code)
      assert state.status == :lobby
    end
  end

  describe "join_game/2" do
    test "joins a player to a game by code" do
      %{code: code} = game_fixture()
      player = user_fixture()
      assert {:ok, _ticket} = Game.join_game(code, player.id)
    end

    test "returns error for unknown code" do
      assert {:error, :game_not_found} = Game.join_game("NOPE-00", 1)
    end
  end

  describe "game_state/1" do
    test "returns state for active game" do
      %{code: code} = game_fixture()
      assert {:ok, state} = Game.game_state(code)
      assert state.status == :lobby
    end

    test "returns error for unknown game" do
      assert {:error, :game_not_found} = Game.game_state("NOPE-00")
    end
  end

  describe "start_game/2" do
    test "starts a game" do
      %{code: code, host: host} = game_fixture()
      player = user_fixture()
      Game.join_game(code, player.id)
      assert :ok = Game.start_game(code, host.id)
    end
  end
end

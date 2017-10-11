defmodule Moth.HousieTest do
  use Moth.DataCase

  alias Moth.Housie

  describe "games" do
    alias Moth.Housie.Game

    @valid_attrs %{}
    @update_attrs %{}
    @invalid_attrs %{}

    def game_fixture(attrs \\ %{}) do
      {:ok, game} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Housie.create_game()

      game
    end

    test "list_games/0 returns all games" do
      game = game_fixture()
      assert Housie.list_games() == [game]
    end

    test "get_game!/1 returns the game with given id" do
      game = game_fixture()
      assert Housie.get_game!(game.id) == game
    end

    test "create_game/1 with valid data creates a game" do
      assert {:ok, %Game{} = game} = Housie.create_game(@valid_attrs)
    end

    test "create_game/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Housie.create_game(@invalid_attrs)
    end

    test "update_game/2 with valid data updates the game" do
      game = game_fixture()
      assert {:ok, game} = Housie.update_game(game, @update_attrs)
      assert %Game{} = game
    end

    test "update_game/2 with invalid data returns error changeset" do
      game = game_fixture()
      assert {:error, %Ecto.Changeset{}} = Housie.update_game(game, @invalid_attrs)
      assert game == Housie.get_game!(game.id)
    end

    test "delete_game/1 deletes the game" do
      game = game_fixture()
      assert {:ok, %Game{}} = Housie.delete_game(game)
      assert_raise Ecto.NoResultsError, fn -> Housie.get_game!(game.id) end
    end

    test "change_game/1 returns a game changeset" do
      game = game_fixture()
      assert %Ecto.Changeset{} = Housie.change_game(game)
    end
  end

  describe "prizes" do
    alias Moth.Housie.Prize

    @valid_attrs %{name: "some name", reward: "some reward"}
    @update_attrs %{name: "some updated name", reward: "some updated reward"}
    @invalid_attrs %{name: nil, reward: nil}

    def prize_fixture(attrs \\ %{}) do
      {:ok, prize} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Housie.create_prize()

      prize
    end

    test "list_prizes/0 returns all prizes" do
      prize = prize_fixture()
      assert Housie.list_prizes() == [prize]
    end

    test "get_prize!/1 returns the prize with given id" do
      prize = prize_fixture()
      assert Housie.get_prize!(prize.id) == prize
    end

    test "create_prize/1 with valid data creates a prize" do
      assert {:ok, %Prize{} = prize} = Housie.create_prize(@valid_attrs)
      assert prize.name == "some name"
      assert prize.reward == "some reward"
    end

    test "create_prize/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Housie.create_prize(@invalid_attrs)
    end

    test "update_prize/2 with valid data updates the prize" do
      prize = prize_fixture()
      assert {:ok, prize} = Housie.update_prize(prize, @update_attrs)
      assert %Prize{} = prize
      assert prize.name == "some updated name"
      assert prize.reward == "some updated reward"
    end

    test "update_prize/2 with invalid data returns error changeset" do
      prize = prize_fixture()
      assert {:error, %Ecto.Changeset{}} = Housie.update_prize(prize, @invalid_attrs)
      assert prize == Housie.get_prize!(prize.id)
    end

    test "delete_prize/1 deletes the prize" do
      prize = prize_fixture()
      assert {:ok, %Prize{}} = Housie.delete_prize(prize)
      assert_raise Ecto.NoResultsError, fn -> Housie.get_prize!(prize.id) end
    end

    test "change_prize/1 returns a prize changeset" do
      prize = prize_fixture()
      assert %Ecto.Changeset{} = Housie.change_prize(prize)
    end
  end

  describe "game_moderators" do
    alias Moth.Housie.GameModerator

    @valid_attrs %{}
    @update_attrs %{}
    @invalid_attrs %{}

    def game_moderator_fixture(attrs \\ %{}) do
      {:ok, game_moderator} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Housie.create_game_moderator()

      game_moderator
    end

    test "list_game_moderators/0 returns all game_moderators" do
      game_moderator = game_moderator_fixture()
      assert Housie.list_game_moderators() == [game_moderator]
    end

    test "get_game_moderator!/1 returns the game_moderator with given id" do
      game_moderator = game_moderator_fixture()
      assert Housie.get_game_moderator!(game_moderator.id) == game_moderator
    end

    test "create_game_moderator/1 with valid data creates a game_moderator" do
      assert {:ok, %GameModerator{} = game_moderator} = Housie.create_game_moderator(@valid_attrs)
    end

    test "create_game_moderator/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Housie.create_game_moderator(@invalid_attrs)
    end

    test "update_game_moderator/2 with valid data updates the game_moderator" do
      game_moderator = game_moderator_fixture()
      assert {:ok, game_moderator} = Housie.update_game_moderator(game_moderator, @update_attrs)
      assert %GameModerator{} = game_moderator
    end

    test "update_game_moderator/2 with invalid data returns error changeset" do
      game_moderator = game_moderator_fixture()
      assert {:error, %Ecto.Changeset{}} = Housie.update_game_moderator(game_moderator, @invalid_attrs)
      assert game_moderator == Housie.get_game_moderator!(game_moderator.id)
    end

    test "delete_game_moderator/1 deletes the game_moderator" do
      game_moderator = game_moderator_fixture()
      assert {:ok, %GameModerator{}} = Housie.delete_game_moderator(game_moderator)
      assert_raise Ecto.NoResultsError, fn -> Housie.get_game_moderator!(game_moderator.id) end
    end

    test "change_game_moderator/1 returns a game_moderator changeset" do
      game_moderator = game_moderator_fixture()
      assert %Ecto.Changeset{} = Housie.change_game_moderator(game_moderator)
    end
  end
end

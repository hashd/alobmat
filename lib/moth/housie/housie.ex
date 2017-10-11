defmodule Moth.Housie do
  @moduledoc """
  The Housie context.
  """

  import Ecto.Query, warn: false
  alias Moth.Repo

  alias Moth.Housie.{Game, Server}

  def start_game(%{interval: interval, user: _u, details: _d} = data) do
    game = create_game(data)
    {:ok, pid} = Server.start_link(game.id, interval)
    Registry.register(Moth.Games, game.id, pid)
    {:ok, game}
  end

  @doc """
  Returns the list of games.

  ## Examples

      iex> list_games()
      [%Game{}, ...]

  """
  def list_games do
    Repo.all(Game)
  end

  @doc """
  Gets a single game.

  Raises `Ecto.NoResultsError` if the Game does not exist.

  ## Examples

      iex> get_game!(123)
      %Game{}

      iex> get_game!(456)
      ** (Ecto.NoResultsError)

  """
  def get_game!(id), do: Repo.get!(Game, id)

  @doc """
  Creates a game.

  ## Examples

      iex> create_game(%{field: value})
      {:ok, %Game{}}

      iex> create_game(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_game(attrs \\ %{}) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a game.

  ## Examples

      iex> update_game(game, %{field: new_value})
      {:ok, %Game{}}

      iex> update_game(game, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_game(%Game{} = game, attrs) do
    game
    |> Game.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Game.

  ## Examples

      iex> delete_game(game)
      {:ok, %Game{}}

      iex> delete_game(game)
      {:error, %Ecto.Changeset{}}

  """
  def delete_game(%Game{} = game) do
    Repo.delete(game)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking game changes.

  ## Examples

      iex> change_game(game)
      %Ecto.Changeset{source: %Game{}}

  """
  def change_game(%Game{} = game) do
    Game.changeset(game, %{})
  end

  alias Moth.Housie.Prize

  @doc """
  Returns the list of prizes.

  ## Examples

      iex> list_prizes()
      [%Prize{}, ...]

  """
  def list_prizes do
    Repo.all(Prize)
  end

  @doc """
  Gets a single prize.

  Raises `Ecto.NoResultsError` if the Prize does not exist.

  ## Examples

      iex> get_prize!(123)
      %Prize{}

      iex> get_prize!(456)
      ** (Ecto.NoResultsError)

  """
  def get_prize!(id), do: Repo.get!(Prize, id)

  @doc """
  Creates a prize.

  ## Examples

      iex> create_prize(%{field: value})
      {:ok, %Prize{}}

      iex> create_prize(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_prize(attrs \\ %{}) do
    %Prize{}
    |> Prize.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a prize.

  ## Examples

      iex> update_prize(prize, %{field: new_value})
      {:ok, %Prize{}}

      iex> update_prize(prize, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_prize(%Prize{} = prize, attrs) do
    prize
    |> Prize.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Prize.

  ## Examples

      iex> delete_prize(prize)
      {:ok, %Prize{}}

      iex> delete_prize(prize)
      {:error, %Ecto.Changeset{}}

  """
  def delete_prize(%Prize{} = prize) do
    Repo.delete(prize)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking prize changes.

  ## Examples

      iex> change_prize(prize)
      %Ecto.Changeset{source: %Prize{}}

  """
  def change_prize(%Prize{} = prize) do
    Prize.changeset(prize, %{})
  end

  alias Moth.Housie.GameModerator

  @doc """
  Returns the list of game_moderators.

  ## Examples

      iex> list_game_moderators()
      [%GameModerator{}, ...]

  """
  def list_game_moderators do
    Repo.all(GameModerator)
  end

  @doc """
  Gets a single game_moderator.

  Raises `Ecto.NoResultsError` if the Game moderator does not exist.

  ## Examples

      iex> get_game_moderator!(123)
      %GameModerator{}

      iex> get_game_moderator!(456)
      ** (Ecto.NoResultsError)

  """
  def get_game_moderator!(id), do: Repo.get!(GameModerator, id)

  @doc """
  Creates a game_moderator.

  ## Examples

      iex> create_game_moderator(%{field: value})
      {:ok, %GameModerator{}}

      iex> create_game_moderator(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_game_moderator(attrs \\ %{}) do
    %GameModerator{}
    |> GameModerator.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a game_moderator.

  ## Examples

      iex> update_game_moderator(game_moderator, %{field: new_value})
      {:ok, %GameModerator{}}

      iex> update_game_moderator(game_moderator, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_game_moderator(%GameModerator{} = game_moderator, attrs) do
    game_moderator
    |> GameModerator.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a GameModerator.

  ## Examples

      iex> delete_game_moderator(game_moderator)
      {:ok, %GameModerator{}}

      iex> delete_game_moderator(game_moderator)
      {:error, %Ecto.Changeset{}}

  """
  def delete_game_moderator(%GameModerator{} = game_moderator) do
    Repo.delete(game_moderator)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking game_moderator changes.

  ## Examples

      iex> change_game_moderator(game_moderator)
      %Ecto.Changeset{source: %GameModerator{}}

  """
  def change_game_moderator(%GameModerator{} = game_moderator) do
    GameModerator.changeset(game_moderator, %{})
  end
end

defmodule Moth.Housie.GameModerator do
  use Ecto.Schema
  import Ecto.Changeset
  alias Moth.Housie.GameModerator


  schema "game_moderators" do
    field :game_id, :id
    field :user_id, :id
  end

  @doc false
  def changeset(%GameModerator{} = game_moderator, attrs) do
    game_moderator
    |> cast(attrs, [])
    |> validate_required([])
  end
end

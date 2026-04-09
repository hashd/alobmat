defmodule Moth.Housie.GameModerator do
  use Ecto.Schema
  import Ecto.Changeset
  schema "game_moderators" do
    field :game_id, :string
    field :user_id, :id
  end

  @doc false
  def changeset(game_moderator, attrs) do
    game_moderator
    |> cast(attrs, [])
    |> validate_required([])
  end
end

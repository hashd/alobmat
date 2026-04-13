defmodule Mocha.Game.Player do
  @moduledoc "Ecto schema for the game_players table."
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :user_id, :tickets, :prizes_won, :bogeys]}
  schema "game_players" do
    field :tickets, {:array, :map}, default: []
    field :prizes_won, {:array, :string}, default: []
    field :bogeys, :integer, default: 0

    belongs_to :game, Mocha.Game.Record
    belongs_to :user, Mocha.Auth.User

    timestamps(updated_at: false)
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:game_id, :user_id, :tickets, :prizes_won, :bogeys])
    |> validate_required([:game_id, :user_id])
    |> unique_constraint([:game_id, :user_id])
  end
end

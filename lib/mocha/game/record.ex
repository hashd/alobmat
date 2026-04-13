defmodule Mocha.Game.Record do
  @moduledoc "Ecto schema for the games table."
  use Ecto.Schema
  import Ecto.Changeset

  alias Mocha.Game.StatusEnum

  @derive {Jason.Encoder,
           only: [:id, :code, :name, :host_id, :status, :settings, :started_at, :finished_at]}
  schema "games" do
    field :code, :string
    field :name, :string
    field :status, StatusEnum, default: :lobby
    field :settings, :map, default: %{}
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :snapshot, :map

    belongs_to :host, Mocha.Auth.User
    has_many :players, Mocha.Game.Player, foreign_key: :game_id

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :code,
      :name,
      :host_id,
      :status,
      :settings,
      :started_at,
      :finished_at,
      :snapshot
    ])
    |> validate_required([:code, :name, :host_id])
    |> unique_constraint(:code)
  end
end

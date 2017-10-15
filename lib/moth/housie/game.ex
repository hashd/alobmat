defmodule Moth.Housie.Game do
  use Ecto.Schema
  import Ecto.Changeset
  alias Moth.Housie.{Game, Prize}
  alias Moth.{Accounts, Accounts.User}

  @serialized_fields [:id, :name, :status, :details, :owner, :moderators, :prizes, :started_at, :finished_at]

  @primary_key {:id, :string, autogenerate: false}
  @derive {Poison.Encoder, only: @serialized_fields}
  schema "games" do
    field         :name,        :string
    field         :status,      :string,          default: "running"
    belongs_to    :owner,       User
    has_many      :prizes,      Prize
    many_to_many  :moderators,  User,             join_through: "game_moderators", on_replace: :mark_as_invalid
    field         :started_at,  :utc_datetime
    field         :finished_at, :utc_datetime

    embeds_one    :details,     GameDetail do
      field :interval, :integer,  default: 45
      field :bulletin, :string,   default: ""
      field :about,    :string,   default: ""
    end

    timestamps()
  end

  @doc false
  def changeset(%Game{} = game, attrs) do
    game
    |> cast(attrs, [:id, :name, :status, :owner_id, :started_at, :finished_at])
    |> cast_embed(:details, with: &details_changeset/2)
    |> put_assoc(:moderators, parse_moderators(attrs))
    |> validate_required([:name])
  end

  defp details_changeset(details, attrs) do
    details
    |> cast(attrs, [:interval, :bulletin, :about])
  end

  defp parse_moderators(attrs)  do
    insert_and_get_all(attrs[:moderators] || [])
  end

  defp insert_and_get_all([]) do
    []
  end
  defp insert_and_get_all(moderators) do
    Accounts.get_users(moderators)
  end
end

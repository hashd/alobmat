defmodule Moth.Housie.Game do
  use Ecto.Schema
  import Ecto.Changeset
  alias Moth.Housie.{Game, Prize}
  alias Moth.Accounts.User

  @derive {Poison.Encoder, only: [:id, :name, :status, :details]}
  schema "games" do
    field         :name,        :string
    field         :status,      :string,      default: "running"
    belongs_to    :owner,       User
    has_many      :prizes,      Prize
    many_to_many  :moderators,  User,         join_through: :game_moderators
    
    embeds_one    :details,     GameDetail do
      field :interval, :integer,  default: 45
      field :bulletin, :string,   default: ""
    end

    timestamps()
  end

  @doc false
  def changeset(%Game{} = game, attrs) do
    game
    |> cast(attrs, [:name, :status])
    |> cast_embed(:details, with: &details_changeset/2)
    |> validate_required([:name])
  end

  def details_changeset(details, attrs) do
    details
    |> cast(attrs, [:interval, :bulletin])
  end
end

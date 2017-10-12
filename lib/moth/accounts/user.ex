defmodule Moth.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset
  alias Moth.Accounts.{User, Credential}

  @derive {Poison.Encoder, only: [:id, :name, :avatar_url, :google_id]}
  schema "users" do
    field :avatar_url, :string
    field :google_id, :string
    field :name, :string
    field :email, :string
    has_one :credential, Credential

    timestamps()
  end

  @doc false
  def changeset(%User{} = user, attrs) do
    user
    |> cast(attrs, [:name, :avatar_url, :google_id])
    |> validate_required([:name, :avatar_url, :google_id])
  end
end

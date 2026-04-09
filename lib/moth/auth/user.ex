defmodule Moth.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :email, :name, :avatar_url]}
  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string

    has_many :identities, Moth.Auth.UserIdentity
    has_many :tokens, Moth.Auth.UserToken

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar_url])
    |> validate_required([:email, :name])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
  end
end

defmodule Mocha.Auth.UserIdentity do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_identities" do
    field :provider, :string
    field :provider_uid, :string

    belongs_to :user, Mocha.Auth.User

    timestamps()
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_uid, :user_id])
    |> validate_required([:provider, :provider_uid, :user_id])
    |> unique_constraint([:provider, :provider_uid])
    |> unique_constraint([:user_id, :provider])
  end
end

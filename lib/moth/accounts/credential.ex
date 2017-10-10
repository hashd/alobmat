defmodule Moth.Accounts.Credential do
  use Ecto.Schema
  import Ecto.Changeset
  alias Moth.Accounts.{Credential, User}

  schema "credentials" do
    field :email, :string
    field :token, :string
    field :provider, :string
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(%Credential{} = credential, attrs) do
    credential
    |> cast(attrs, [:email, :token, :provider])
    |> validate_required([:email, :token, :provider])
    |> unique_constraint(:email)
  end
end

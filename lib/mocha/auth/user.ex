defmodule Mocha.Auth.User do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:id, :email, :name, :avatar_url, :phone]}
  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string
    field :phone, :string

    has_many :identities, Mocha.Auth.UserIdentity
    has_many :tokens, Mocha.Auth.UserToken

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :avatar_url, :phone])
    |> validate_required([:name])
    |> maybe_validate_email()
    |> validate_contact_present()
    |> unique_constraint(:email)
    |> unique_constraint(:phone)
  end

  def phone_registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:phone, :name])
    |> validate_required([:phone, :name])
    |> validate_format(:phone, ~r/^\+91[6-9]\d{9}$/, message: "must be a valid Indian mobile number")
    |> unique_constraint(:phone)
  end

  defp maybe_validate_email(changeset) do
    case get_field(changeset, :email) do
      nil -> changeset
      _ -> validate_format(changeset, :email, ~r/^[^\s]+@[^\s]+$/)
    end
  end

  defp validate_contact_present(changeset) do
    email = get_field(changeset, :email)
    phone = get_field(changeset, :phone)

    if is_nil(email) and is_nil(phone) do
      add_error(changeset, :base, "must have at least a phone or email")
    else
      changeset
    end
  end
end

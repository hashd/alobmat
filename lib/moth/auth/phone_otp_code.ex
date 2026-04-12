defmodule Moth.Auth.PhoneOtpCode do
  use Ecto.Schema
  import Ecto.Changeset

  schema "phone_otp_codes" do
    field :phone, :string
    field :hashed_code, :binary
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    field :attempt_count, :integer, default: 0

    timestamps(updated_at: false)
  end

  def changeset(otp_code, attrs) do
    otp_code
    |> cast(attrs, [:phone, :hashed_code, :expires_at])
    |> validate_required([:phone, :hashed_code, :expires_at])
  end
end

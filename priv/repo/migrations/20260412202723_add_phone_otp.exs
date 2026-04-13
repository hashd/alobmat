defmodule Mocha.Repo.Migrations.AddPhoneOtp do
  use Ecto.Migration

  def change do
    # Add phone to users, make email nullable
    alter table(:users) do
      add :phone, :string, size: 20
      modify :email, :string, null: true, from: {:string, null: false}
    end

    create unique_index(:users, [:phone])

    # OTP codes table
    create table(:phone_otp_codes) do
      add :phone, :string, size: 20, null: false
      add :hashed_code, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :attempt_count, :integer, null: false, default: 0

      timestamps(updated_at: false)
    end

    create index(:phone_otp_codes, [:phone, :expires_at])
  end
end

defmodule Mocha.Repo.Migrations.CreateV2Tables do
  use Ecto.Migration

  def change do
    # Drop old tables (from POC)
    drop_if_exists table(:game_moderators)
    drop_if_exists table(:prizes)
    drop_if_exists table(:games)
    drop_if_exists table(:credentials)
    drop_if_exists table(:users)

    create table(:users) do
      add :email, :string, null: false
      add :name, :string, null: false
      add :avatar_url, :string

      timestamps()
    end

    create unique_index(:users, [:email])

    create table(:user_identities) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :provider_uid, :string, null: false

      timestamps()
    end

    create unique_index(:user_identities, [:provider, :provider_uid])
    create unique_index(:user_identities, [:user_id, :provider])

    create table(:user_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      timestamps(updated_at: false)
    end

    create index(:user_tokens, [:token])
    create index(:user_tokens, [:user_id, :context])

    create table(:games) do
      add :code, :string, null: false
      add :name, :string, null: false
      add :host_id, references(:users, on_delete: :nothing), null: false
      add :status, :string, null: false, default: "lobby"
      add :settings, :map, default: %{}
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :snapshot, :map

      timestamps()
    end

    create unique_index(:games, [:code])
    create index(:games, [:status])
    create index(:games, [:host_id])

    create table(:game_players) do
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :ticket, :map
      add :prizes_won, {:array, :string}, default: []
      add :bogeys, :integer, default: 0

      timestamps(updated_at: false)
    end

    create unique_index(:game_players, [:game_id, :user_id])
  end
end

defmodule Moth.Repo.Migrations.CreateGameModerators do
  use Ecto.Migration

  def change do
    create table(:game_moderators, primary_key: false) do
      add :game_id, references(:games, on_delete: :nothing)
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:game_moderators, [:game_id])
    create index(:game_moderators, [:user_id])
  end
end

defmodule Moth.Repo.Migrations.CreatePrizes do
  use Ecto.Migration

  def change do
    create table(:prizes) do
      add :name, :string
      add :reward, :string
      add :game_id, references(:games, on_delete: :nothing)
      add :winner_user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:prizes, [:game_id])
    create index(:prizes, [:winner_user_id])
  end
end

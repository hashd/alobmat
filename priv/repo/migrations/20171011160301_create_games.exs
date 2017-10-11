defmodule Moth.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :name, :string
      add :owner_id, references(:users, on_delete: :nothing)
      add :details, :map

      timestamps()
    end

  end
end

defmodule Moth.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games, primary_key: false) do
      add :id,   :string, primary_key: true, null: false
      add :name, :string
      add :owner_id, references(:users, on_delete: :nothing)
      add :details, :map

      timestamps()
    end

  end
end

defmodule Moth.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :name, :string
      add :interval, :integer
      add :owner_id, references(:users, on_delete: :nothing)

      timestamps()
    end

  end
end

defmodule Moth.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string
      add :avatar_url, :string
      add :google_id, :string

      timestamps()
    end

  end
end

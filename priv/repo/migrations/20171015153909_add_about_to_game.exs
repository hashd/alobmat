defmodule Moth.Repo.Migrations.AddAboutToGame do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :about, :string
    end
  end
end

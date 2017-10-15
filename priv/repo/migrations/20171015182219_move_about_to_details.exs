defmodule Moth.Repo.Migrations.MoveAboutToDetails do
  use Ecto.Migration

  def change do
    alter table(:games) do
      remove :about
    end
  end
end

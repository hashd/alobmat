defmodule Moth.Repo.Migrations.DropTimestampsFromGameModerators do
  use Ecto.Migration

  def change do
    alter table(:game_moderators) do
      remove :inserted_at
      remove :updated_at
    end
  end
end

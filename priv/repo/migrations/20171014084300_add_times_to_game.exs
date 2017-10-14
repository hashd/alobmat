defmodule Moth.Repo.Migrations.AddTimesToGame do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add   :started_at,    :utc_datetime
      add   :finished_at,   :utc_datetime
    end
  end
end

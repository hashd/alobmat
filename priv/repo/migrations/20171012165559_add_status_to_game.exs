defmodule Moth.Repo.Migrations.AddStatusToGame do
  use Ecto.Migration

  def change do
    alter table :games do
      add :status, :string
    end
  end
end

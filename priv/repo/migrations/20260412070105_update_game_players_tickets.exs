defmodule Mocha.Repo.Migrations.UpdateGamePlayersTickets do
  use Ecto.Migration

  def change do
    alter table(:game_players) do
      remove :ticket
      add :tickets, {:array, :map}, default: []
    end
  end
end

defmodule Mocha.Game.ServerRecoveryTest do
  use Mocha.DataCase, async: false

  alias Mocha.Game.{Server, Record, Player}
  alias Mocha.Repo

  import Mocha.AuthFixtures

  @default_settings %{
    interval: 10,
    bogey_limit: 3,
    enabled_prizes: [:early_five, :top_line, :middle_line, :bottom_line, :full_house]
  }

  test "snapshot persists board state to DB" do
    host = user_fixture()
    player = user_fixture()
    code = "SNAP-#{System.unique_integer([:positive])}"

    {:ok, record} =
      Repo.insert(%Record{
        code: code,
        name: "Snapshot Test",
        host_id: host.id,
        status: :lobby,
        settings: @default_settings
      })

    {:ok, pid} =
      start_supervised(
        {Server,
         %{
           code: code,
           name: "Snapshot Test",
           host_id: host.id,
           settings: @default_settings,
           game_record_id: record.id
         }}
      )

    Server.join(pid, player.id)
    Server.start_game(pid, host.id)

    state = Server.get_state(pid)
    assert state.status == :running
  end

  test "player join writes through to DB" do
    host = user_fixture()
    player = user_fixture()
    code = "JOIN-#{System.unique_integer([:positive])}"

    {:ok, record} =
      Repo.insert(%Record{
        code: code,
        name: "Join Test",
        host_id: host.id,
        status: :lobby,
        settings: @default_settings
      })

    {:ok, pid} =
      start_supervised(
        {Server,
         %{
           code: code,
           name: "Join Test",
           host_id: host.id,
           settings: @default_settings,
           game_record_id: record.id
         }}
      )

    Server.join(pid, player.id)
    Server.start_game(pid, host.id)

    assert Repo.get_by(Player, game_id: record.id, user_id: player.id)
  end
end

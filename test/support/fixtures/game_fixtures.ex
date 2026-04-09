defmodule Moth.GameFixtures do
  @moduledoc "Test helpers for creating game entities."

  alias Moth.Game

  import Moth.AuthFixtures

  @default_settings %{interval: 10, bogey_limit: 3, enabled_prizes: [:early_five, :top_line, :middle_line, :bottom_line, :full_house]}

  def game_fixture(attrs \\ %{}) do
    host = attrs[:host] || user_fixture()

    {:ok, code} =
      Game.create_game(host.id, %{
        name: attrs[:name] || "Test Game",
        settings: attrs[:settings] || @default_settings
      })

    %{code: code, host: host}
  end
end

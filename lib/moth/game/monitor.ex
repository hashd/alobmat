defmodule Moth.Game.Monitor do
  @moduledoc """
  Tracks active games, publishes telemetry metrics, reaps stale games.

  - Lobby games idle for > 1 hour are reaped
  - Finished games past cooldown (30 min) are reaped
  - Reconstructs state from Registry on init (crash-safe)
  """
  use GenServer
  require Logger

  @check_interval :timer.minutes(1)
  @lobby_timeout :timer.hours(1)
  @finished_cooldown :timer.minutes(30)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    schedule_check()
    {:ok, rebuild_state()}
  end

  @impl true
  def handle_info(:check_games, _state) do
    state = rebuild_state()
    reap_stale_games(state)
    emit_telemetry(state)
    schedule_check()
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp rebuild_state do
    games =
      Registry.select(Moth.Game.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])

    %{game_count: length(games), games: games}
  end

  defp reap_stale_games(%{games: games}) do
    now = System.monotonic_time(:millisecond)

    Enum.each(games, fn {code, pid, meta} ->
      try do
        state = GenServer.call(pid, :state, 5_000)

        cond do
          state.status == :lobby and stale?(meta, now, @lobby_timeout) ->
            Logger.info("Reaping stale lobby game: #{code}")
            DynamicSupervisor.terminate_child(Moth.Game.DynSup, pid)

          state.status == :finished and stale?(meta, now, @finished_cooldown) ->
            Logger.info("Reaping finished game: #{code}")
            DynamicSupervisor.terminate_child(Moth.Game.DynSup, pid)

          true ->
            :ok
        end
      catch
        :exit, _ -> :ok
      end
    end)
  end

  defp stale?(%{started_at: started_at}, now, timeout) when is_integer(started_at) do
    now - started_at > timeout
  end

  defp stale?(_, _, _), do: false

  defp emit_telemetry(%{game_count: count}) do
    :telemetry.execute([:moth, :game, :active_count], %{count: count}, %{})
  end

  defp schedule_check do
    Process.send_after(self(), :check_games, @check_interval)
  end
end

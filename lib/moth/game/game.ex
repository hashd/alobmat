defmodule Moth.Game do
  @moduledoc "The Game context. Public API for game management."

  alias Moth.Game.{Server, Record, Code}
  alias Moth.Repo

  @default_settings %{
    interval: 30,
    bogey_limit: 3,
    enabled_prizes: [:early_five, :top_line, :middle_line, :bottom_line, :full_house]
  }

  def create_game(host_id, attrs) do
    settings = Map.merge(@default_settings, Map.get(attrs, :settings, %{}))
    settings = validate_settings(settings)

    existing_codes =
      Registry.select(Moth.Game.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> MapSet.new()

    code = Code.generate(existing_codes)

    {:ok, record} =
      %Record{}
      |> Record.changeset(%{
        code: code,
        name: attrs[:name] || attrs["name"] || "Untitled Game",
        host_id: host_id,
        settings: settings
      })
      |> Repo.insert()

    {:ok, _pid} =
      DynamicSupervisor.start_child(Moth.Game.DynSup, {
        Server,
        %{
          code: code,
          name: record.name,
          host_id: host_id,
          settings: settings,
          game_record_id: record.id
        }
      })

    {:ok, code}
  end

  def join_game(code, user_id) do
    with_server(code, fn pid -> Server.join(pid, user_id) end)
  end

  def game_state(code) do
    with_server(code, fn pid -> {:ok, Server.get_state(pid)} end)
  end

  def start_game(code, host_id) do
    with_server(code, fn pid -> Server.start_game(pid, host_id) end)
  end

  def pause(code, host_id) do
    with_server(code, fn pid -> Server.pause(pid, host_id) end)
  end

  def resume(code, host_id) do
    with_server(code, fn pid -> Server.resume(pid, host_id) end)
  end

  def end_game(code, host_id) do
    with_server(code, fn pid -> Server.end_game(pid, host_id) end)
  end

  def claim_prize(code, user_id, prize) do
    with_server(code, fn pid -> Server.claim_prize(pid, user_id, prize) end)
  end

  def send_chat(code, user_id, text) do
    with_server(code, fn pid -> Server.send_chat(pid, user_id, text) end)
  end

  def player_left(code, user_id) do
    case lookup(code) do
      {:ok, pid} -> Server.player_left(pid, user_id)
      _ -> :ok
    end
  end

  defp with_server(code, fun) do
    case lookup(code) do
      {:ok, pid} -> fun.(pid)
      :error -> {:error, :game_not_found}
    end
  end

  defp lookup(code) do
    case Registry.lookup(Moth.Game.Registry, code) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp validate_settings(settings) do
    settings
    |> Map.update(:interval, 30, &clamp(&1, 10, 120))
    |> Map.update(:bogey_limit, 3, &clamp(&1, 1, 10))
  end

  defp clamp(val, min_val, max_val), do: val |> max(min_val) |> min(max_val)
end

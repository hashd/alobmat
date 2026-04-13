defmodule Mocha.Game do
  @moduledoc "The Game context. Public API for game management."

  alias Mocha.Game.{Server, Record, Code}
  alias Mocha.Repo

  @default_settings %{
    interval: 30,
    bogey_limit: 3,
    default_ticket_count: 1,
    enabled_prizes: [:early_five, :top_line, :middle_line, :bottom_line, :full_house],
    visibility: "public",
    join_secret: nil
  }

  @max_active_games_per_user 5

  def create_game(host_id, attrs) do
    # Limit active games per host using Registry metadata
    active_host_games =
      Registry.select(Mocha.Game.Registry, [{{:_, :_, :"$1"}, [], [:"$1"]}])
      |> Enum.count(fn meta ->
        meta.host_id == host_id and meta.status in [:lobby, :running, :paused]
      end)

    if active_host_games >= @max_active_games_per_user do
      {:error, :too_many_games}
    else
      do_create_game(host_id, attrs)
    end
  end

  defp do_create_game(host_id, attrs) do
    settings = Map.merge(@default_settings, Map.get(attrs, :settings, %{}))
    settings = validate_settings(settings)

    existing_codes =
      Registry.select(Mocha.Game.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])
      |> MapSet.new()

    code = Code.generate(existing_codes)
    name = non_empty(attrs[:name]) || non_empty(attrs["name"]) || "Untitled Game"

    # Use transaction to ensure DB record and GenServer are created atomically
    result =
      Repo.transaction(fn ->
        case %Record{}
             |> Record.changeset(%{code: code, name: name, host_id: host_id, settings: settings})
             |> Repo.insert() do
          {:ok, record} ->
            case DynamicSupervisor.start_child(Mocha.Game.DynSup, {
                   Server,
                   %{
                     code: code,
                     name: record.name,
                     host_id: host_id,
                     settings: settings,
                     game_record_id: record.id
                   }
                 }) do
              {:ok, _pid} -> code
              {:error, reason} -> Repo.rollback(reason)
            end

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, code} -> {:ok, code}
      {:error, _} -> {:error, :create_failed}
    end
  end

  def join_game(code, user_id, secret \\ nil) do
    with_server(code, fn pid -> Server.join(pid, user_id, secret) end)
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

  def strike_out(code, user_id, number) do
    with_server(code, fn pid -> Server.strike_out(pid, user_id, number) end)
  end

  def claim_prize(code, user_id, ticket_id, prize) do
    with_server(code, fn pid -> Server.claim_prize(pid, user_id, ticket_id, prize) end)
  end

  def set_ticket_count(code, host_id, user_id, count) do
    with_server(code, fn pid -> Server.set_ticket_count(pid, host_id, user_id, count) end)
  end

  def send_chat(code, user_id, text) do
    with_server(code, fn pid -> Server.send_chat(pid, user_id, text) end)
  end

  def strike_out_async(code, user_id, number) do
    case lookup(code) do
      {:ok, pid} -> Server.strike_out_async(pid, user_id, number)
      _ -> :ok
    end
  end

  def send_reaction(code, user_id, emoji) do
    with_server(code, fn pid -> Server.send_reaction(pid, user_id, emoji) end)
  end

  def player_left(code, user_id) do
    case lookup(code) do
      {:ok, pid} -> Server.player_left(pid, user_id)
      _ -> :ok
    end
  end

  def recent_games(user_id, limit \\ 5) do
    import Ecto.Query

    from(g in Record,
      where: g.host_id == ^user_id,
      order_by: [desc: g.inserted_at],
      limit: ^limit,
      select: %{
        code: g.code,
        name: g.name,
        status: g.status,
        inserted_at: g.inserted_at
      }
    )
    |> Repo.all()
  end

  def list_public_games do
    # Read from Registry metadata — no GenServer calls needed
    Registry.select(Mocha.Game.Registry, [{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
    |> Enum.filter(fn {_code, meta} ->
      meta.visibility == "public" and meta.status in [:lobby, :running]
    end)
    |> Enum.map(fn {code, meta} ->
      %{
        code: code,
        name: meta.name,
        status: meta.status,
        host_id: meta.host_id,
        players_count: meta.player_count
      }
    end)
  end

  def clone_game(old_code, host_id) do
    case game_state(old_code) do
      {:ok, state} ->
        create_game(host_id, %{name: state[:name] || "Rematch", settings: state.settings})

      {:error, _} = err ->
        err
    end
  end

  defp with_server(code, fun) do
    case lookup(code) do
      {:ok, pid} -> fun.(pid)
      :error -> {:error, :game_not_found}
    end
  end

  defp lookup(code) do
    case Registry.lookup(Mocha.Game.Registry, code) do
      [{pid, _}] -> {:ok, pid}
      [] -> :error
    end
  end

  defp validate_settings(settings) do
    settings
    |> Map.update(:interval, 30, &clamp(&1, 5, 120))
    |> Map.update(:bogey_limit, 3, &clamp(&1, 1, 10))
    |> Map.update(:default_ticket_count, 1, &clamp(&1, 1, 6))
  end

  defp clamp(val, min_val, max_val), do: val |> max(min_val) |> min(max_val)

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(s) when is_binary(s), do: s
  defp non_empty(_), do: nil
end

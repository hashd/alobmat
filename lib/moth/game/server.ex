defmodule Moth.Game.Server do
  @moduledoc """
  GenServer managing a single Tambola game.
  One process per game, under Moth.Game.DynSup.
  """
  use GenServer
  require Logger
  import Ecto.Query

  alias Moth.Game.{Board, Ticket, Prize}

  defstruct [
    :id,
    :code,
    :host_id,
    :timer_ref,
    :next_pick_at,
    :host_disconnect_ref,
    :started_at,
    :finished_at,
    status: :lobby,
    board: nil,
    tickets: %{},
    players: MapSet.new(),
    struck: %{},
    prizes: %{},
    bogeys: %{},
    settings: %{},
    chat_timestamps: %{},
    reaction_timestamps: %{}
  ]

  # Client API

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg)
  end

  def get_state(pid), do: GenServer.call(pid, :state)
  def join(pid, user_id, secret \\ nil), do: GenServer.call(pid, {:join, user_id, secret})
  def start_game(pid, host_id), do: GenServer.call(pid, {:start_game, host_id})
  def pause(pid, host_id), do: GenServer.call(pid, {:pause, host_id})
  def resume(pid, host_id), do: GenServer.call(pid, {:resume, host_id})
  def end_game(pid, host_id), do: GenServer.call(pid, {:end_game, host_id})
  def claim_prize(pid, user_id, prize), do: GenServer.call(pid, {:claim, user_id, prize})
  def strike_out(pid, user_id, number), do: GenServer.call(pid, {:strike_out, user_id, number})
  def strike_out_async(pid, user_id, number), do: GenServer.cast(pid, {:strike_out, user_id, number})
  def send_chat(pid, user_id, text), do: GenServer.call(pid, {:chat, user_id, text})
  def send_reaction(pid, user_id, emoji), do: GenServer.call(pid, {:reaction, user_id, emoji})
  def player_left(pid, user_id), do: GenServer.cast(pid, {:player_left, user_id})

  # Server callbacks

  @impl true
  def init(%{
        code: code,
        name: name,
        host_id: host_id,
        settings: settings,
        game_record_id: record_id
      }) do
    Registry.register(Moth.Game.Registry, code, %{
      name: name,
      started_at: System.monotonic_time(:millisecond)
    })

    enabled = Map.get(settings, :enabled_prizes, Prize.all_prizes())
    prizes = Map.new(enabled, fn p -> {p, nil} end)

    state = %__MODULE__{
      id: record_id,
      code: code,
      host_id: host_id,
      board: Board.new(),
      settings: settings,
      prizes: prizes,
      status: :lobby
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, sanitize_state(state), state}
  end

  def handle_call({:join, _user_id, _secret}, _from, %{status: :finished} = state) do
    {:reply, {:error, :game_finished}, state}
  end

  def handle_call({:join, user_id, secret}, _from, state) do
    visibility = Map.get(state.settings, :visibility) || Map.get(state.settings, "visibility", "public")
    join_secret = Map.get(state.settings, :join_secret) || Map.get(state.settings, "join_secret")

    if visibility == "private" and user_id != state.host_id and secret != join_secret do
      {:reply, {:error, :invalid_secret}, state}
    else
      if Map.has_key?(state.tickets, user_id) do
        {:reply, {:ok, state.tickets[user_id]}, state}
      else
        state = %{state | players: MapSet.put(state.players, user_id)}
        
        ticket = hd(Ticket.generate_strip())
        state = %{state | tickets: Map.put(state.tickets, user_id, ticket)}

        if state.id && ticket do
        Moth.Repo.insert!(
          %Moth.Game.Player{game_id: state.id, user_id: user_id, tickets: [Ticket.to_map(ticket)]},
          on_conflict: :nothing
        )
      end

      broadcast(state.code, :player_joined, %{user_id: user_id})
      {:reply, {:ok, ticket}, state}
    end
  end
  end

  def handle_call({:start_game, host_id}, _from, %{host_id: host_id, status: :lobby} = state) do
    tickets =
      state.players
      |> Enum.reduce(state.tickets, fn player_id, acc ->
        if Map.has_key?(acc, player_id) do
          acc
        else
          Map.put(acc, player_id, hd(Ticket.generate_strip()))
        end
      end)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    interval = Map.get(state.settings, :interval, 30)
    next_pick_at = DateTime.add(now, interval)
    timer_ref = schedule_pick(interval)

    state = %{
      state
      | status: :running,
        tickets: tickets,
        started_at: now,
        timer_ref: timer_ref,
        next_pick_at: next_pick_at
    }

    if state.id do
      Enum.each(tickets, fn {player_id, ticket} ->
        Moth.Repo.insert!(
          %Moth.Game.Player{game_id: state.id, user_id: player_id, tickets: [Ticket.to_map(ticket)]},
          on_conflict: :nothing
        )
      end)
    end

    broadcast(state.code, :status, %{status: :running, started_at: now})
    {:reply, :ok, state}
  end

  def handle_call({:start_game, _other_id}, _from, state) do
    {:reply, {:error, :not_host}, state}
  end

  def handle_call({:pause, host_id}, _from, %{host_id: host_id, status: :running} = state) do
    cancel_timer(state.timer_ref)
    state = %{state | status: :paused, timer_ref: nil}
    broadcast(state.code, :status, %{status: :paused, by: host_id})
    {:reply, :ok, state}
  end

  def handle_call({:pause, _}, _from, state) do
    {:reply, {:error, :not_host}, state}
  end

  def handle_call({:resume, host_id}, _from, %{host_id: host_id, status: :paused} = state) do
    interval = Map.get(state.settings, :interval, 30)
    next_pick_at = DateTime.add(DateTime.utc_now(), interval)
    timer_ref = schedule_pick(interval)

    state = %{
      state
      | status: :running,
        timer_ref: timer_ref,
        next_pick_at: next_pick_at,
        host_disconnect_ref: cancel_and_nil(state.host_disconnect_ref)
    }

    broadcast(state.code, :status, %{status: :running, by: host_id})
    {:reply, :ok, state}
  end

  def handle_call({:resume, host_id}, _from, %{host_id: host_id} = state) do
    {:reply, {:error, :not_paused}, state}
  end

  def handle_call({:resume, _}, _from, state) do
    {:reply, {:error, :not_host}, state}
  end

  def handle_call({:end_game, host_id}, _from, %{host_id: host_id} = state) do
    state = finish_game(state)
    {:reply, :ok, state}
  end

  def handle_call({:end_game, _}, _from, state) do
    {:reply, {:error, :not_host}, state}
  end

  def handle_call({:strike_out, user_id, number}, _from, state) do
    picked_set = MapSet.new(state.board.picks)

    cond do
      state.status not in [:running, :paused] ->
        {:reply, {:error, :game_not_running}, state}

      not Map.has_key?(state.tickets, user_id) ->
        {:reply, {:error, :not_in_game}, state}

      not MapSet.member?(picked_set, number) ->
        {:reply, {:error, :not_picked}, state}

      true ->
        ticket = state.tickets[user_id]

        if MapSet.member?(ticket.numbers, number) do
          user_struck = Map.get(state.struck, user_id, MapSet.new())

          state = %{
            state
            | struck: Map.put(state.struck, user_id, MapSet.put(user_struck, number))
          }

          {:reply, :ok, state}
        else
          {:reply, {:error, :not_on_ticket}, state}
        end
    end
  end

  def handle_call({:claim, user_id, prize_type}, _from, state) do
    bogey_limit = Map.get(state.settings, :bogey_limit, 3)
    user_bogeys = Map.get(state.bogeys, user_id, 0)

    cond do
      state.status != :running ->
        {:reply, {:error, :game_not_running}, state}

      user_bogeys >= bogey_limit ->
        {:reply, {:error, :disqualified}, state}

      not Map.has_key?(state.tickets, user_id) ->
        {:reply, {:error, :not_in_game}, state}

      not Map.has_key?(state.prizes, prize_type) ->
        {:reply, {:error, :prize_not_enabled}, state}

      state.prizes[prize_type] != nil ->
        {:reply, {:error, :already_claimed}, state}

      true ->
        ticket = state.tickets[user_id]
        struck = Map.get(state.struck, user_id, MapSet.new())

        case Prize.check_claim(prize_type, ticket, struck) do
          :valid ->
            state = %{state | prizes: Map.put(state.prizes, prize_type, user_id)}

            if state.id do
              Moth.Repo.update_all(
                from(p in Moth.Game.Player,
                  where: p.game_id == ^state.id and p.user_id == ^user_id
                ),
                push: [prizes_won: to_string(prize_type)]
              )
            end

            broadcast(state.code, :prize_claimed, %{prize: prize_type, winner_id: user_id})
            {:reply, {:ok, prize_type}, state}

          :invalid ->
            new_bogeys = user_bogeys + 1
            remaining = bogey_limit - new_bogeys
            state = %{state | bogeys: Map.put(state.bogeys, user_id, new_bogeys)}

            broadcast(state.code, :bogey, %{
              user_id: user_id,
              prize: prize_type,
              remaining: remaining
            })

            {:reply, {:error, :bogey, remaining}, state}
        end
    end
  end

  def handle_call({:chat, user_id, text}, _from, state) do
    now = System.monotonic_time(:millisecond)
    last = Map.get(state.chat_timestamps, user_id, now - 1_000)

    if now - last < 1_000 do
      {:reply, {:error, :rate_limited}, state}
    else
      state = %{state | chat_timestamps: Map.put(state.chat_timestamps, user_id, now)}
      broadcast(state.code, :chat, %{user_id: user_id, text: text})
      {:reply, :ok, state}
    end
  end

  def handle_call({:reaction, user_id, emoji}, _from, state) do
    now = System.monotonic_time(:millisecond)
    last = Map.get(state.reaction_timestamps, user_id, now - 1_000)

    if now - last < 1_000 do
      {:reply, {:error, :rate_limited}, state}
    else
      state = %{state | reaction_timestamps: Map.put(state.reaction_timestamps, user_id, now)}
      broadcast(state.code, :reaction, %{user_id: user_id, emoji: emoji})
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast({:player_left, user_id}, %{host_id: host_id} = state) when user_id == host_id do
    ref = Process.send_after(self(), :host_disconnect_timeout, :timer.seconds(60))
    {:noreply, %{state | host_disconnect_ref: ref}}
  end

  def handle_cast({:player_left, user_id}, state) do
    broadcast(state.code, :player_left, %{user_id: user_id})
    {:noreply, state}
  end

  def handle_cast({:strike_out, user_id, number}, state) do
    picked_set = MapSet.new(state.board.picks)

    cond do
      state.status not in [:running, :paused] ->
        {:noreply, state}

      not Map.has_key?(state.tickets, user_id) ->
        {:noreply, state}

      not MapSet.member?(picked_set, number) ->
        {:noreply, state}

      true ->
        ticket = state.tickets[user_id]

        if MapSet.member?(ticket.numbers, number) do
          user_struck = Map.get(state.struck, user_id, MapSet.new())

          state = %{
            state
            | struck: Map.put(state.struck, user_id, MapSet.put(user_struck, number))
          }

          {:noreply, state}
        else
          {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(:pick, %{status: :running} = state) do
    case Board.pick(state.board) do
      {:finished, board} ->
        state = %{state | board: board}
        state = finish_game(state)
        {:noreply, state}

      {number, board} ->
        interval = Map.get(state.settings, :interval, 30)
        next_pick_at = DateTime.add(DateTime.utc_now(), interval)
        timer_ref = schedule_pick(interval)

        state = %{state | board: board, timer_ref: timer_ref, next_pick_at: next_pick_at}

        broadcast(state.code, :pick, %{
          number: number,
          count: board.count,
          next_pick_at: next_pick_at,
          server_now: DateTime.utc_now()
        })

        if rem(board.count, 5) == 0, do: snapshot(state)

        {:noreply, state}
    end
  end

  def handle_info(:pick, state), do: {:noreply, state}

  def handle_info(:host_disconnect_timeout, %{status: :running} = state) do
    cancel_timer(state.timer_ref)

    state = %{state | status: :paused, timer_ref: nil, host_disconnect_ref: nil}

    broadcast(state.code, :status, %{status: :paused, by: :system, reason: :host_disconnected})
    {:noreply, state}
  end

  def handle_info(:host_disconnect_timeout, state) do
    {:noreply, %{state | host_disconnect_ref: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  # Private

  defp finish_game(state) do
    cancel_timer(state.timer_ref)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    state = %{state | status: :finished, timer_ref: nil, finished_at: now}

    broadcast(state.code, :status, %{status: :finished})
    snapshot(state)
    state
  end

  defp schedule_pick(interval_seconds) do
    Process.send_after(self(), :pick, :timer.seconds(interval_seconds))
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp cancel_and_nil(nil), do: nil

  defp cancel_and_nil(ref) do
    Process.cancel_timer(ref)
    nil
  end

  defp broadcast(code, event, payload) do
    Phoenix.PubSub.broadcast(Moth.PubSub, "game:#{code}", {event, payload})
  end

  defp snapshot(%{id: nil}), do: :ok

  defp snapshot(%{id: id, board: board, status: status}) do
    Moth.Repo.update_all(
      from(g in Moth.Game.Record, where: g.id == ^id),
      set: [
        snapshot: Board.to_map(board),
        status: to_string(status),
        updated_at: DateTime.utc_now()
      ]
    )

    :ok
  end

  defp sanitize_state(state) do
    # Compute prize_progress while tickets/struck are still raw structs/MapSets
    prize_progress = compute_prize_progress(state.tickets, state.struck, state.prizes)

    Map.from_struct(state)
    |> Map.drop([:timer_ref, :host_disconnect_ref, :chat_timestamps, :reaction_timestamps])
    |> Map.put(:prize_progress, stringify_prize_progress(prize_progress))
    |> Map.update(:players, [], &MapSet.to_list/1)
    |> Map.update(:struck, %{}, fn struck ->
      Map.new(struck, fn {k, v} -> {k, MapSet.to_list(v)} end)
    end)
    |> Map.update(:board, nil, fn
      %Board{} = b -> Board.to_map(b)
      other -> other
    end)
    |> Map.update(:tickets, %{}, fn tickets ->
      Map.new(tickets, fn
        {k, %Ticket{} = t} -> {k, Ticket.to_map(t)}
        {k, v} -> {k, v}
      end)
    end)
  end

  defp stringify_prize_progress(progress) do
    Map.new(progress, fn {user_id, prizes} ->
      {user_id, Map.new(prizes, fn {prize, val} -> {to_string(prize), val} end)}
    end)
  end

  defp compute_prize_progress(tickets, struck, prizes) do
    Map.new(tickets, fn {user_id, ticket} ->
      user_struck = Map.get(struck, user_id, MapSet.new())

      progress =
        Map.new(prizes, fn {prize_type, _winner} ->
          {required, struck_count} = prize_requirement(prize_type, ticket, user_struck)
          {prize_type, %{struck: struck_count, required: required}}
        end)

      {user_id, progress}
    end)
  end

  defp prize_requirement(:top_line, ticket, struck), do: line_progress(ticket, 0, struck)
  defp prize_requirement(:middle_line, ticket, struck), do: line_progress(ticket, 1, struck)
  defp prize_requirement(:bottom_line, ticket, struck), do: line_progress(ticket, 2, struck)
  defp prize_requirement(:early_five, _ticket, struck), do: {5, min(MapSet.size(struck), 5)}

  defp prize_requirement(:full_house, ticket, struck) do
    total = MapSet.size(ticket.numbers)
    hit = MapSet.size(MapSet.intersection(ticket.numbers, struck))
    {total, hit}
  end

  defp line_progress(ticket, row_index, struck) do
    row_numbers = Enum.at(ticket.rows, row_index) |> Enum.reject(&is_nil/1) |> MapSet.new()
    hit = MapSet.size(MapSet.intersection(row_numbers, struck))
    {MapSet.size(row_numbers), hit}
  end
end

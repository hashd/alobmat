defmodule MochaWeb.GameChannel do
  @moduledoc "Phoenix Channel for real-time Tambola game communication."

  use Phoenix.Channel

  alias Mocha.Game

  @impl true
  def join("game:" <> code, params, socket) do
    current_user = socket.assigns.current_user

    case Game.game_state(code) do
      {:ok, _state} ->
        case Game.join_game(code, current_user.id, params["secret"]) do
          {:error, :invalid_secret} ->
            {:error, %{reason: "invalid_secret"}}

          _ ->
            {:ok, state} = Game.game_state(code)

            # Phoenix automatically subscribes the channel to its own topic ("game:{code}").
            # We only need to manually subscribe to presence.
            :ok = Phoenix.PubSub.subscribe(Mocha.PubSub, "game:#{code}:presence")
            send(self(), {:after_join, code})

        # Enrich players with names, ticket_count, prizes_won, and bogeys
        user_names = Mocha.Auth.get_users_map(state.players)
        default_tc = Map.get(state.settings, :default_ticket_count, 1)
        players = Enum.map(state.players, fn uid ->
          %{
            user_id: uid,
            name: Map.get(user_names, uid, "Unknown"),
            ticket_count: Map.get(state.player_ticket_counts, uid, default_tc),
            prizes_won: state.prizes
              |> Enum.filter(fn {_p, winner} -> winner == uid end)
              |> Enum.map(fn {p, _} -> to_string(p) end),
            bogeys: Map.get(state.bogeys || %{}, uid, 0)
          }
        end)

        # state is already sanitized: board is a map, players is a list,
        # tickets and struck are already converted, prize_progress is computed
        my_ticket_ids = Map.get(state.ticket_owners, current_user.id, [])
        active_count = Map.get(state.player_ticket_counts, current_user.id, default_tc)
        my_tickets = my_ticket_ids |> Enum.take(active_count) |> Enum.map(fn id -> state.tickets[id] end) |> Enum.reject(&is_nil/1)
        my_struck = get_in(state, [:struck, current_user.id]) || []

        reply = %{
          code: state.code,
          name: Map.get(state, :name),
          status: to_string(state.status),
          host_id: state.host_id,
          settings: format_settings(state.settings),
          board: state.board,
          players: players,
          prizes: format_prizes(state.prizes),
          prize_progress: Map.get(state, :prize_progress, %{}),
          my_tickets: my_tickets,
          my_struck: my_struck
        }

            {:ok, reply, assign(socket, :game_code, code)}
        end

      {:error, _} ->
        {:error, %{reason: "game_not_found"}}
    end
  end

  @impl true
  def handle_info({:after_join, code}, socket) do
    MochaWeb.Presence.track_player(socket, code, socket.assigns.current_user)
    {:noreply, socket}
  end

  # PubSub -> Channel event translation

  def handle_info({:pick, payload}, socket) do
    push(socket, "number_picked", %{
      number: payload.number,
      count: payload.count,
      next_pick_at: format_datetime(payload.next_pick_at),
      server_now: format_datetime(payload.server_now)
    })

    {:noreply, socket}
  end

  def handle_info({:status, payload}, socket) do
    push(socket, "status_changed", %{status: to_string(payload.status)})
    {:noreply, socket}
  end

  def handle_info({:prize_claimed, payload}, socket) do
    push(socket, "prize_claimed", %{
      prize: to_string(payload.prize),
      winner_id: payload.winner_id,
      winner_name: Map.get(payload, :winner_name)
    })

    {:noreply, socket}
  end

  def handle_info({:bogey, payload}, socket) do
    # Server broadcasts :remaining; we expose it as bogeys_remaining to clients
    push(socket, "bogey", %{
      user_id: payload.user_id,
      bogeys_remaining: payload.remaining
    })

    {:noreply, socket}
  end

  def handle_info({:player_joined, payload}, socket) do
    user_id = payload.user_id
    name = case Mocha.Auth.get_users_map([user_id]) do
      %{^user_id => n} -> n
      _ -> "Unknown"
    end
    push(socket, "player_joined", %{
      user_id: user_id,
      name: name,
      ticket_count: Map.get(payload, :ticket_count, 1)
    })
    {:noreply, socket}
  end

  def handle_info({:player_left, payload}, socket) do
    push(socket, "player_left", %{user_id: payload.user_id})
    {:noreply, socket}
  end

  def handle_info({:chat, payload}, socket) do
    user_id = payload.user_id
    sender_name = case MochaWeb.Presence.list_players(socket.assigns.game_code) do
      %{^user_id => %{metas: [%{name: name} | _]}} -> name
      _ -> user_id
    end

    push(socket, "chat", %{
      id: "chat-#{System.unique_integer([:positive])}",
      user_id: payload.user_id,
      user_name: sender_name,
      text: payload.text,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })

    {:noreply, socket}
  end

  def handle_info({:reaction, payload}, socket) do
    push(socket, "reaction", %{emoji: payload.emoji, user_id: payload.user_id})
    {:noreply, socket}
  end

  def handle_info({:ticket_count_updated, payload}, socket) do
    push(socket, "ticket_count_updated", %{user_id: payload.user_id, count: payload.count})
    {:noreply, socket}
  end

  def handle_info({:player_tickets_updated, payload}, socket) do
    # Only send ticket data to the player who owns them — prevent other players from seeing tickets
    if payload.user_id == socket.assigns.current_user.id do
      push(socket, "player_tickets_updated", %{user_id: payload.user_id, tickets: payload.tickets})
    end
    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    if code = socket.assigns[:game_code] do
      user = socket.assigns[:current_user]
      if user, do: Mocha.Game.player_left(code, user.id)
    end
    :ok
  end

  # Inbound messages (client -> server)

  @impl true
  def handle_in("strike", %{"number" => number}, socket) do
    user = socket.assigns.current_user
    code = socket.assigns.game_code

    result =
      case Game.strike_out(code, user.id, number) do
        :ok -> "ok"
        {:error, _} -> "rejected"
      end

    push(socket, "strike_result", %{number: number, result: result})
    {:noreply, socket}
  end

  def handle_in("claim", %{"prize" => prize, "ticket_id" => ticket_id}, socket) do
    valid_prizes = ~w(early_five top_line middle_line bottom_line full_house)

    if prize in valid_prizes do
      user = socket.assigns.current_user
      code = socket.assigns.game_code
      prize_atom = String.to_existing_atom(prize)

      case Game.claim_prize(code, user.id, ticket_id, prize_atom) do
        {:ok, _prize} ->
          {:noreply, socket}

        {:error, :bogey, remaining} ->
          push(socket, "claim_rejection", %{reason: "bogey", bogeys_remaining: remaining})
          {:noreply, socket}

        {:error, reason} ->
          push(socket, "claim_rejection", %{reason: to_string(reason)})
          {:noreply, socket}
      end
    else
      push(socket, "claim_rejection", %{reason: "invalid_prize"})
      {:noreply, socket}
    end
  end

  def handle_in("reaction", %{"emoji" => emoji}, socket) do
    Game.send_reaction(socket.assigns.game_code, socket.assigns.current_user.id, emoji)
    {:noreply, socket}
  end

  def handle_in("chat", %{"text" => text}, socket) do
    Game.send_chat(socket.assigns.game_code, socket.assigns.current_user.id, text)
    {:noreply, socket}
  end

  # Helpers

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(other), do: other

  defp format_settings(settings) do
    %{
      interval: settings.interval,
      bogey_limit: settings.bogey_limit,
      default_ticket_count: Map.get(settings, :default_ticket_count, 1),
      enabled_prizes: Enum.map(settings.enabled_prizes, &to_string/1)
    }
  end

  defp format_prizes(prizes) when is_map(prizes) do
    Map.new(prizes, fn {prize, winner_id} ->
      {to_string(prize), %{claimed: not is_nil(winner_id), winner_id: winner_id}}
    end)
  end
end

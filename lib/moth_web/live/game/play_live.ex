defmodule MothWeb.Game.PlayLive do
  use MothWeb, :live_view

  alias Moth.Game

  def mount(%{"code" => code}, _session, socket) do
    code = String.upcase(code)

    case Game.game_state(code) do
      {:ok, _state} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Moth.PubSub, "game:#{code}")
          Game.join_game(code, socket.assigns.current_user.id)
        end

        {:ok, state} = Game.game_state(code)
        user_id = socket.assigns.current_user.id

        socket =
          socket
          |> assign(:code, code)
          |> assign(:game_state, state)
          |> assign(:ticket, state.tickets[user_id])
          |> assign(:picks, state.board.picks)
          |> assign(:struck, Map.get(state.struck, user_id, []))
          |> assign(:prizes, state.prizes)
          |> assign(:status, state.status)
          |> assign(:auto_strike, false)
          |> assign(:messages, [])
          |> assign(:events, [])

        {:ok, socket}

      {:error, :game_not_found} ->
        {:ok, socket |> put_flash(:error, "Game not found.") |> redirect(to: ~p"/")}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Game unavailable.") |> redirect(to: ~p"/")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-xl font-bold"><%= @code %></h1>
          <p class="text-sm text-gray-500">Status: <%= @status %></p>
        </div>
        <label class="flex items-center gap-2 text-sm text-gray-600">
          <input
            type="checkbox"
            phx-click="toggle_auto_strike"
            checked={@auto_strike}
            class="rounded border-gray-300"
          /> Auto-strike
        </label>
      </div>

      <%= if @ticket do %>
        <.ticket_grid
          ticket={@ticket}
          picks={@picks}
          struck={@struck}
          interactive={@status in [:running, :paused]}
        />
        <MothWeb.GameComponents.claim_buttons prizes={@prizes} enabled={@status == :running} />
      <% else %>
        <p class="text-gray-600">Waiting for the game to start...</p>
      <% end %>

      <div class="mt-4">
        <h3 class="text-sm font-semibold text-gray-700">Picked Numbers</h3>
        <div class="flex flex-wrap gap-1 mt-1">
          <%= for num <- Enum.reverse(@picks) do %>
            <span class="inline-flex items-center justify-center h-8 w-8 rounded-full bg-indigo-100 text-indigo-800 text-xs font-bold">
              <%= num %>
            </span>
          <% end %>
        </div>
      </div>

      <div class="mt-4 space-y-1">
        <%= for event <- Enum.take(@events, 10) do %>
          <p class="text-sm text-gray-600"><%= event %></p>
        <% end %>
      </div>

      <div class="mt-4">
        <form phx-submit="chat" class="flex gap-2">
          <input
            type="text"
            name="text"
            placeholder="Chat..."
            class="flex-1 rounded-lg border-gray-300 text-sm"
            autocomplete="off"
          />
          <button type="submit" class="rounded-lg bg-gray-200 px-3 py-2 text-sm">Send</button>
        </form>
        <div class="mt-2 space-y-1 max-h-32 overflow-y-auto">
          <%= for msg <- Enum.take(@messages, 20) do %>
            <p class="text-sm"><strong><%= msg.user %></strong>: <%= msg.text %></p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("strike_out", %{"number" => number_str}, socket) do
    number = String.to_integer(number_str)

    case Game.strike_out(socket.assigns.code, socket.assigns.current_user.id, number) do
      :ok ->
        {:noreply, update(socket, :struck, fn struck -> [number | struck] end)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_auto_strike", _params, socket) do
    {:noreply, assign(socket, :auto_strike, !socket.assigns.auto_strike)}
  end

  def handle_event("claim", %{"prize" => prize}, socket) do
    prize_atom = String.to_existing_atom(prize)
    code = socket.assigns.code
    user_id = socket.assigns.current_user.id

    case Game.claim_prize(code, user_id, prize_atom) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "You won #{prize}!")}

      {:error, :already_claimed} ->
        {:noreply, put_flash(socket, :error, "Prize already claimed!")}

      {:error, :bogey, remaining} ->
        {:noreply, put_flash(socket, :error, "Invalid claim! #{remaining} strikes remaining.")}

      {:error, :disqualified} ->
        {:noreply, put_flash(socket, :error, "You are disqualified from claiming.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot claim: #{reason}")}
    end
  end

  def handle_event("chat", %{"text" => text}, socket) do
    Game.send_chat(socket.assigns.code, socket.assigns.current_user.id, text)
    {:noreply, socket}
  end

  def handle_info({:pick, payload}, socket) do
    socket = update(socket, :picks, fn picks -> [payload.number | picks] end)
    socket = assign(socket, :next_pick_at, payload[:next_pick_at])

    # Auto-strike if enabled and the number is on our ticket
    socket =
      if socket.assigns.auto_strike && socket.assigns.ticket do
        ticket_numbers = socket.assigns.ticket["numbers"] || []
        ticket_set = MapSet.new(ticket_numbers)

        if MapSet.member?(ticket_set, payload.number) do
          Game.strike_out(socket.assigns.code, socket.assigns.current_user.id, payload.number)
          update(socket, :struck, fn struck -> [payload.number | struck] end)
        else
          socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:status, payload}, socket) do
    {:noreply, assign(socket, :status, payload.status)}
  end

  def handle_info({:prize_claimed, payload}, socket) do
    event = "Prize #{payload.prize} won by player #{payload.winner_id}!"

    {:noreply,
     socket
     |> update(:prizes, fn prizes -> Map.put(prizes, payload.prize, payload.winner_id) end)
     |> update(:events, fn events -> [event | events] end)}
  end

  def handle_info({:bogey, payload}, socket) do
    event = "Bogey! Player #{payload.user_id} — #{payload.remaining} strikes left"
    {:noreply, update(socket, :events, fn events -> [event | events] end)}
  end

  def handle_info({:chat, payload}, socket) do
    msg = %{user: "Player #{payload.user_id}", text: payload.text}
    {:noreply, update(socket, :messages, fn msgs -> [msg | msgs] end)}
  end

  def handle_info({:player_joined, _}, socket), do: {:noreply, socket}
  def handle_info({:player_left, _}, socket), do: {:noreply, socket}
  def handle_info(_, socket), do: {:noreply, socket}
end

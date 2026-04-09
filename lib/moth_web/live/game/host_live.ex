defmodule MothWeb.Game.HostLive do
  use MothWeb, :live_view

  alias Moth.Game

  def mount(%{"code" => code}, _session, socket) do
    code = String.upcase(code)

    case Game.game_state(code) do
      {:ok, state} ->
        if state.host_id != socket.assigns.current_user.id do
          {:ok, socket |> put_flash(:error, "You are not the host.") |> redirect(to: ~p"/game/#{code}")}
        else
          if connected?(socket) do
            Phoenix.PubSub.subscribe(Moth.PubSub, "game:#{code}")
          end

          socket =
            socket
            |> assign(:code, code)
            |> assign(:status, state.status)
            |> assign(:picks, state.board.picks)
            |> assign(:prizes, state.prizes)
            |> assign(:player_count, MapSet.size(state.players))

          {:ok, socket}
        end

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Game not found.") |> redirect(to: ~p"/")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Host: <%= @code %></h1>
          <p class="text-sm text-gray-500">Share this code with players</p>
        </div>
        <span class="text-sm text-gray-500"><%= @player_count %> players</span>
      </div>

      <div class="flex gap-3">
        <%= if @status == :lobby do %>
          <button phx-click="start" class="rounded-lg bg-green-600 px-6 py-3 text-white font-semibold hover:bg-green-500">
            Start Game
          </button>
        <% end %>
        <%= if @status == :running do %>
          <button phx-click="pause" class="rounded-lg bg-yellow-600 px-6 py-3 text-white font-semibold hover:bg-yellow-500">
            Pause
          </button>
        <% end %>
        <%= if @status == :paused do %>
          <button phx-click="resume" class="rounded-lg bg-green-600 px-6 py-3 text-white font-semibold hover:bg-green-500">
            Resume
          </button>
        <% end %>
        <%= if @status in [:running, :paused] do %>
          <button phx-click="end_game" class="rounded-lg bg-red-600 px-6 py-3 text-white font-semibold hover:bg-red-500"
            data-confirm="End the game? This cannot be undone.">
            End Game
          </button>
        <% end %>
      </div>

      <div>
        <h3 class="font-semibold">Picked: <%= length(@picks) %>/90</h3>
        <div class="flex flex-wrap gap-1 mt-2">
          <%= for num <- Enum.reverse(@picks) do %>
            <span class="inline-flex items-center justify-center h-8 w-8 rounded-full bg-indigo-100 text-indigo-800 text-xs font-bold">
              <%= num %>
            </span>
          <% end %>
        </div>
      </div>

      <div>
        <h3 class="font-semibold">Prizes</h3>
        <div class="mt-2 space-y-1">
          <%= for {prize, winner} <- @prizes do %>
            <p class="text-sm">
              <%= prize %> — <%= if winner, do: "Won by #{winner}", else: "Unclaimed" %>
            </p>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("start", _, socket) do
    Game.start_game(socket.assigns.code, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("pause", _, socket) do
    Game.pause(socket.assigns.code, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("resume", _, socket) do
    Game.resume(socket.assigns.code, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("end_game", _, socket) do
    Game.end_game(socket.assigns.code, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_info({:pick, payload}, socket) do
    {:noreply, update(socket, :picks, fn picks -> [payload.number | picks] end)}
  end

  def handle_info({:status, payload}, socket) do
    {:noreply, assign(socket, :status, payload.status)}
  end

  def handle_info({:prize_claimed, payload}, socket) do
    {:noreply, update(socket, :prizes, fn prizes -> Map.put(prizes, payload.prize, payload.winner_id) end)}
  end

  def handle_info({:player_joined, _}, socket) do
    {:noreply, update(socket, :player_count, &(&1 + 1))}
  end

  def handle_info({:player_left, _}, socket) do
    {:noreply, update(socket, :player_count, &max(&1 - 1, 0))}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end

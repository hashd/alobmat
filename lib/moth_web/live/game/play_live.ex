defmodule MothWeb.Game.PlayLive do
  @moduledoc """
  Player view for a Tambola/Housie game.

  Renders three states based on `@status`:
  - `:lobby`    — waiting room before the game starts
  - `:running` / `:paused` — active gameplay with ticket, board, prizes, feed
  - `:finished` — game over with winners and confetti
  """
  use MothWeb, :live_view

  alias Moth.Game

  # ── Mount ───────────────────────────────────────────────────────────

  def mount(%{"code" => code}, _session, socket) do
    code = String.upcase(code)
    user_id = socket.assigns.current_user.id

    case Game.game_state(code) do
      {:ok, state} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Moth.PubSub, "game:#{code}")
          Phoenix.PubSub.subscribe(Moth.PubSub, "game:#{code}:presence")
          Game.join_game(code, user_id)
          MothWeb.Presence.track_player(socket, code, socket.assigns.current_user)
        end

        ticket = state.tickets[user_id]
        my_progress = get_in(state, [:prize_progress, user_id]) || %{}

        socket =
          socket
          |> assign(:code, code)
          |> assign(:status, state.status)
          |> assign(:ticket, ticket)
          |> assign(:picks, state.board.picks)
          |> assign(:struck, Map.get(state.struck, user_id, []))
          |> assign(:prizes, state.prizes)
          |> assign(:prize_progress, my_progress)
          |> assign(:auto_strike, false)
          |> assign(:player_count, length(state.players))
          |> assign(:next_pick_at, state[:next_pick_at])
          |> assign(:server_now, state[:started_at] || DateTime.utc_now())
          |> assign(:settings, state[:settings] || %{})
          |> assign(:show_board, false)
          |> assign(:presences, MothWeb.Presence.list_players(code))

        {:ok, socket}

      {:error, :game_not_found} ->
        {:ok, socket |> put_flash(:error, "Game not found.") |> redirect(to: ~p"/")}

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Game unavailable.") |> redirect(to: ~p"/")}
    end
  end

  # ── Render (dispatcher) ────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <div id="play-presence" phx-hook="Presence" class="mx-auto max-w-5xl px-4 pb-28">
      <%= case @status do %>
        <% :lobby -> %>
          <.lobby_view
            code={@code}
            player_count={@player_count}
            prizes={@prizes}
            settings={@settings}
          />
        <% status when status in [:running, :paused] -> %>
          <.gameplay_view
            code={@code}
            status={@status}
            ticket={@ticket}
            picks={@picks}
            struck={@struck}
            prizes={@prizes}
            prize_progress={@prize_progress}
            auto_strike={@auto_strike}
            next_pick_at={@next_pick_at}
            server_now={@server_now}
            player_count={@player_count}
            show_board={@show_board}
            current_user_id={@current_user.id}
          />
        <% :finished -> %>
          <.game_over_view prizes={@prizes} current_user_id={@current_user.id} />
      <% end %>

      <%!-- Floating reactions container --%>
      <div id="floating-reactions" phx-hook="FloatingReaction" class="pointer-events-none fixed inset-0 z-50" />
    </div>
    """
  end

  # ── Lobby View ─────────────────────────────────────────────────────

  attr :code, :string, required: true
  attr :player_count, :integer, required: true
  attr :prizes, :map, required: true
  attr :settings, :map, required: true

  defp lobby_view(assigns) do
    enabled_prizes = Map.get(assigns.settings, :enabled_prizes, Map.keys(assigns.prizes))
    assigns = assign(assigns, :enabled_prizes, enabled_prizes)

    ~H"""
    <div class="flex min-h-[70vh] flex-col items-center justify-center text-center">
      <div class="animate-fade-in-up space-y-6">
        <%!-- Heading --%>
        <div class="space-y-2">
          <h1 class="text-3xl font-bold text-[var(--text-primary)]">
            You're in!
          </h1>
          <p class="text-[var(--text-muted)]">Share this code with friends</p>
        </div>

        <%!-- Game code --%>
        <div
          id="lobby-code"
          phx-hook="CopyCode"
          data-code={@code}
          class="cursor-pointer select-all rounded-2xl bg-[var(--elevated)] px-8 py-4 text-center"
        >
          <span class="font-mono text-4xl font-black tracking-widest text-accent">
            <%= @code %>
          </span>
          <p class="mt-1 text-xs text-[var(--text-muted)]">Tap to copy</p>
        </div>

        <%!-- Player count --%>
        <div class="animate-fade-in-up stagger-2">
          <div class="inline-flex items-center gap-2 rounded-full bg-[var(--surface)] border border px-4 py-2">
            <span class="relative flex h-2.5 w-2.5">
              <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-success opacity-75" />
              <span class="relative inline-flex h-2.5 w-2.5 rounded-full bg-success" />
            </span>
            <span class="text-sm font-semibold text-[var(--text-primary)]">
              <%= @player_count %> player<%= if @player_count != 1, do: "s" %>
            </span>
          </div>
        </div>

        <%!-- Waiting message with pulsing dots --%>
        <p class="animate-fade-in-up stagger-3 text-sm text-[var(--text-muted)]">
          Waiting for host to start<span class="inline-flex w-6 animate-pulse">...</span>
        </p>

        <%!-- Enabled prizes --%>
        <div class="animate-fade-in-up stagger-4 space-y-2">
          <p class="text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">Prizes</p>
          <div class="flex flex-wrap justify-center gap-2">
            <span
              :for={prize <- @enabled_prizes}
              class="inline-flex items-center rounded-full border border px-3 py-1 text-sm font-medium text-[var(--text-secondary)]"
            >
              <%= prize_label(prize) %>
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Gameplay View ──────────────────────────────────────────────────

  attr :code, :string, required: true
  attr :status, :atom, required: true
  attr :ticket, :map, required: true
  attr :picks, :list, required: true
  attr :struck, :any, required: true
  attr :prizes, :map, required: true
  attr :prize_progress, :map, required: true
  attr :auto_strike, :boolean, required: true
  attr :next_pick_at, :any, required: true
  attr :server_now, :any, required: true
  attr :player_count, :integer, required: true
  attr :show_board, :boolean, required: true
  attr :current_user_id, :any, required: true

  defp gameplay_view(assigns) do
    latest = if assigns.picks != [], do: hd(assigns.picks), else: nil
    ticket_numbers = if assigns.ticket, do: assigns.ticket["numbers"] || assigns.ticket[:numbers] || [], else: []
    assigns = assigns |> assign(:latest, latest) |> assign(:ticket_numbers, ticket_numbers)

    ~H"""
    <%!-- Sticky status bar --%>
    <div class="sticky top-0 z-30 -mx-4 mb-4 border-b border-[var(--border)] bg-[var(--bg)]/95 px-4 py-2 backdrop-blur-sm">
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <span
            id="game-code"
            phx-hook="CopyCode"
            data-code={@code}
            class="cursor-pointer font-mono text-sm font-bold text-[var(--text-primary)]"
          >
            <%= @code %>
          </span>
          <.badge variant={if @status == :running, do: "live", else: "paused"}>
            <%= if @status == :running, do: "Live", else: "Paused" %>
          </.badge>
        </div>
        <div class="flex items-center gap-3">
          <label class="flex items-center gap-1.5 text-xs text-[var(--text-muted)] cursor-pointer">
            <div class="relative">
              <input
                type="checkbox"
                phx-click="toggle_auto_strike"
                checked={@auto_strike}
                class="peer sr-only"
              />
              <div class="h-5 w-9 rounded-full bg-[var(--elevated)] peer-checked:bg-accent transition-colors" />
              <div class="absolute left-0.5 top-0.5 h-4 w-4 rounded-full bg-white shadow transition-transform peer-checked:translate-x-4" />
            </div>
            Auto
          </label>
        </div>
      </div>
    </div>

    <%!-- Two-column layout on desktop --%>
    <div class="md:grid md:grid-cols-[1fr_340px] md:gap-6">
      <%!-- Main column --%>
      <div class="space-y-4">
        <%!-- Countdown ring --%>
        <div class="flex justify-center">
          <.countdown_ring
            next_pick_at={@next_pick_at}
            server_now={@server_now}
            status={@status}
          />
        </div>

        <%!-- Ticket --%>
        <%= if @ticket do %>
          <.ticket_grid
            ticket={@ticket}
            picks={@picks}
            struck={@struck}
            interactive={@status == :running}
            status={@status}
          />
        <% end %>

        <%!-- Prize chips — horizontal scroll --%>
        <div class="flex gap-2 overflow-x-auto pb-1 scrollbar-none">
          <.prize_chip
            :for={{prize, winner} <- @prizes}
            prize={prize}
            label={prize_label(prize)}
            winner={winner}
            progress={Map.get(@prize_progress, prize)}
            current_user_id={@current_user_id}
            enabled={@status == :running}
          />
        </div>

        <%!-- Picked numbers --%>
        <div class="space-y-2">
          <div class="flex items-center justify-between">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
              Picked (<%= length(@picks) %>/90)
            </h3>
          </div>
          <div class="flex flex-wrap gap-1.5">
            <.number_pill
              :for={num <- Enum.reverse(@picks)}
              number={num}
              latest={num == @latest}
            />
          </div>
        </div>

        <%!-- Board — visible section on desktop --%>
        <div class="hidden md:block">
          <.card>
            <h3 class="mb-2 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">Board</h3>
            <.board picks={@picks} ticket_numbers={@ticket_numbers} />
          </.card>
        </div>
      </div>

      <%!-- Sidebar (desktop) / below content (mobile): Activity feed --%>
      <div class="mt-4 md:mt-0 md:flex md:flex-col md:h-[calc(100vh-8rem)]">
        <.live_component module={MothWeb.Game.ActivityFeed} id="feed" />
      </div>
    </div>

    <%!-- Mobile FAB: Board --%>
    <button
      phx-click={JS.push("open_board") |> JS.dispatch("phx:show-board", to: "#board-sheet")}
      class="fixed bottom-20 right-4 z-40 flex h-12 w-12 items-center justify-center rounded-full bg-accent text-white shadow-lg md:hidden"
      aria-label="Open board"
    >
      <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6ZM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25ZM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6ZM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25a2.25 2.25 0 0 1-2.25-2.25v-2.25Z" />
      </svg>
    </button>

    <%!-- Mobile Board Bottom Sheet --%>
    <.bottom_sheet id="board-sheet">
      <h3 class="mb-3 text-center text-sm font-semibold text-[var(--text-muted)]">Board</h3>
      <.board picks={@picks} ticket_numbers={@ticket_numbers} />
    </.bottom_sheet>

    <%!-- Reactions bar --%>
    <div class="fixed bottom-4 left-1/2 z-40 -translate-x-1/2">
      <div class="flex items-center gap-1 rounded-full bg-[var(--surface)] border border px-2 py-1 shadow-lg">
        <button
          :for={emoji <- ~w(👏 🎉 😂 😮 🔥 ❤️)}
          phx-click="reaction"
          phx-value-emoji={emoji}
          class="flex h-9 w-9 items-center justify-center rounded-full text-lg transition-transform hover:scale-125 active:scale-90"
          aria-label={"React with #{emoji}"}
        >
          <%= emoji %>
        </button>
      </div>
    </div>
    """
  end

  # ── Game Over View ─────────────────────────────────────────────────

  attr :prizes, :map, required: true
  attr :current_user_id, :any, required: true

  defp game_over_view(assigns) do
    winners =
      assigns.prizes
      |> Enum.filter(fn {_prize, winner} -> winner != nil end)
      |> Enum.map(fn {prize, winner_id} ->
        %{prize: prize, label: prize_label(prize), winner_id: winner_id, is_me: winner_id == assigns.current_user_id}
      end)

    assigns = assign(assigns, :winners, winners)

    ~H"""
    <div
      id="game-over"
      phx-hook="Confetti"
      class="flex min-h-[70vh] flex-col items-center justify-center text-center"
    >
      <div class="animate-scale-in space-y-8">
        <div class="space-y-2">
          <h1 class="text-4xl font-black text-[var(--text-primary)]">
            Game Over
          </h1>
          <p class="text-[var(--text-muted)]">Thanks for playing!</p>
        </div>

        <%!-- Prize winners --%>
        <div :if={@winners != []} class="space-y-3">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
            Winners
          </h2>
          <div class="space-y-2">
            <div
              :for={w <- @winners}
              class={[
                "flex items-center justify-between rounded-xl px-4 py-3 border border",
                if(w.is_me, do: "bg-accent/10 border-accent/40", else: "bg-[var(--surface)]")
              ]}
            >
              <span class="font-semibold text-[var(--text-primary)]"><%= w.label %></span>
              <span class={[
                "text-sm font-medium",
                if(w.is_me, do: "text-accent", else: "text-[var(--text-muted)]")
              ]}>
                <%= if w.is_me, do: "You won! 🏆", else: "Player #{w.winner_id}" %>
              </span>
            </div>
          </div>
        </div>

        <div :if={@winners == []} class="animate-fade-in-up stagger-2">
          <p class="text-[var(--text-muted)]">No prizes were claimed this game.</p>
        </div>

        <%!-- Back to home --%>
        <div class="animate-fade-in-up stagger-3">
          <.button phx-click="leave_game" size="lg">
            Back to Home
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # ── Event Handlers ─────────────────────────────────────────────────

  def handle_event("strike_out", %{"number" => num_str}, socket) do
    number = String.to_integer(num_str)

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

  def handle_event("claim", %{"prize" => prize_str}, socket) do
    prize_atom = String.to_existing_atom(prize_str)
    code = socket.assigns.code
    user_id = socket.assigns.current_user.id

    case Game.claim_prize(code, user_id, prize_atom) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "You won #{prize_label(prize_atom)}!")}

      {:error, :already_claimed} ->
        {:noreply, put_flash(socket, :error, "Prize already claimed!")}

      {:error, :bogey, remaining} ->
        {:noreply, put_flash(socket, :error, "Invalid claim! #{remaining} bogey strikes remaining.")}

      {:error, :disqualified} ->
        {:noreply, put_flash(socket, :error, "You are disqualified from claiming.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Cannot claim: #{reason}")}
    end
  end

  def handle_event("chat", %{"text" => text}, socket) when is_binary(text) do
    trimmed = text |> String.trim() |> String.slice(0, 200)

    if trimmed != "" do
      Game.send_chat(socket.assigns.code, socket.assigns.current_user.id, trimmed)
    end

    {:noreply, socket}
  end

  def handle_event("chat", %{"message" => text}, socket) when is_binary(text) do
    trimmed = text |> String.trim() |> String.slice(0, 200)

    if trimmed != "" do
      Game.send_chat(socket.assigns.code, socket.assigns.current_user.id, trimmed)
    end

    {:noreply, socket}
  end

  def handle_event("reaction", %{"emoji" => emoji}, socket) do
    Game.send_reaction(socket.assigns.code, socket.assigns.current_user.id, emoji)
    {:noreply, socket}
  end

  def handle_event("open_board", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("leave_game", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_event("away", _params, socket) do
    MothWeb.Presence.update_status(socket, socket.assigns.code, socket.assigns.current_user.id, :away)
    {:noreply, socket}
  end

  def handle_event("online", _params, socket) do
    MothWeb.Presence.update_status(socket, socket.assigns.code, socket.assigns.current_user.id, :online)
    {:noreply, socket}
  end

  # ── PubSub Handlers ────────────────────────────────────────────────

  def handle_info({:pick, payload}, socket) do
    socket =
      socket
      |> update(:picks, fn picks -> [payload.number | picks] end)
      |> assign(:next_pick_at, payload[:next_pick_at])
      |> assign(:server_now, payload[:server_now])

    # Add feed entry
    send_update(MothWeb.Game.ActivityFeed, id: "feed", new_entry: %{
      id: System.unique_integer([:positive]),
      type: :pick,
      text: "Number #{payload.number} picked",
      number: payload.number,
      user_name: nil,
      user_id: nil,
      timestamp: DateTime.utc_now()
    })

    # Auto-strike if enabled and number is on our ticket
    socket =
      if socket.assigns.auto_strike && socket.assigns.ticket do
        ticket_numbers = socket.assigns.ticket["numbers"] || socket.assigns.ticket[:numbers] || []
        ticket_set = MapSet.new(ticket_numbers)

        if MapSet.member?(ticket_set, payload.number) do
          Game.strike_out_async(socket.assigns.code, socket.assigns.current_user.id, payload.number)
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
    socket = assign(socket, :status, payload.status)

    status_text =
      case payload.status do
        :running -> "Game started!"
        :paused -> "Game paused"
        :finished -> "Game over!"
        other -> "Status: #{other}"
      end

    send_update(MothWeb.Game.ActivityFeed, id: "feed", new_entry: %{
      id: System.unique_integer([:positive]),
      type: :system,
      text: status_text,
      number: nil,
      user_name: nil,
      user_id: nil,
      timestamp: DateTime.utc_now()
    })

    # Fire confetti on game finish
    socket =
      if payload.status == :finished do
        push_event(socket, "confetti", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:prize_claimed, payload}, socket) do
    is_me = payload.winner_id == socket.assigns.current_user.id

    send_update(MothWeb.Game.ActivityFeed, id: "feed", new_entry: %{
      id: System.unique_integer([:positive]),
      type: :prize_claimed,
      text: prize_label(payload.prize),
      number: nil,
      user_name: if(is_me, do: "You", else: "Player #{payload.winner_id}"),
      user_id: payload.winner_id,
      timestamp: DateTime.utc_now()
    })

    socket =
      socket
      |> update(:prizes, fn prizes -> Map.put(prizes, payload.prize, payload.winner_id) end)

    # Fire confetti if we won
    socket = if is_me, do: push_event(socket, "confetti", %{}), else: socket

    {:noreply, socket}
  end

  def handle_info({:bogey, payload}, socket) do
    send_update(MothWeb.Game.ActivityFeed, id: "feed", new_entry: %{
      id: System.unique_integer([:positive]),
      type: :bogey,
      text: "#{payload.remaining} strikes left",
      number: nil,
      user_name: "Player #{payload.user_id}",
      user_id: payload.user_id,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  def handle_info({:chat, payload}, socket) do
    send_update(MothWeb.Game.ActivityFeed, id: "feed", new_entry: %{
      id: System.unique_integer([:positive]),
      type: :chat,
      text: payload.text,
      number: nil,
      user_name: "Player #{payload.user_id}",
      user_id: payload.user_id,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  def handle_info({:reaction, payload}, socket) do
    {:noreply, push_event(socket, "reaction", payload)}
  end

  def handle_info({:player_joined, _payload}, socket) do
    {:noreply, update(socket, :player_count, &(&1 + 1))}
  end

  def handle_info({:player_left, _payload}, socket) do
    {:noreply, update(socket, :player_count, &max(&1 - 1, 0))}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :presences, MothWeb.Presence.list_players(socket.assigns.code))}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end

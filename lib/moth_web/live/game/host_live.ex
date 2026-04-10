defmodule MothWeb.Game.HostLive do
  @moduledoc """
  Host dashboard for a Tambola/Housie game.

  Renders three states based on `@status`:
  - `:lobby`              — waiting room with game code, player list, start button
  - `:running` / `:paused` — command center with board, leaderboard, activity feed
  - `:finished`           — game over with prize winners and play-again option
  """
  use MothWeb, :live_view

  alias Moth.Game

  # ── Mount ───────────────────────────────────────────────────────────

  def mount(%{"code" => code}, _session, socket) do
    code = String.upcase(code)
    user_id = socket.assigns.current_user.id

    case Game.game_state(code) do
      {:ok, state} ->
        if state.host_id != user_id do
          {:ok,
           socket
           |> put_flash(:error, "You are not the host.")
           |> redirect(to: ~p"/game/#{code}")}
        else
          if connected?(socket) do
            Phoenix.PubSub.subscribe(Moth.PubSub, "game:#{code}")
            Phoenix.PubSub.subscribe(Moth.PubSub, "game:#{code}:presence")
            MothWeb.Presence.track_player(socket, code, socket.assigns.current_user)
          end

          socket =
            socket
            |> assign(:code, code)
            |> assign(:status, state.status)
            |> assign(:picks, state.board.picks)
            |> assign(:prizes, state.prizes)
            |> assign(:prize_progress, state[:prize_progress] || %{})
            |> assign(:player_count, length(state.players))
            |> assign(:players, state.players)
            |> assign(:tickets, state[:tickets] || %{})
            |> assign(:struck, state[:struck] || %{})
            |> assign(:next_pick_at, state[:next_pick_at])
            |> assign(:server_now, state[:started_at] || DateTime.utc_now())
            |> assign(:settings, state[:settings] || %{})
            |> assign(:game_name, state[:name] || "Untitled Game")
            |> assign(:presences, MothWeb.Presence.list_players(code))

          {:ok, socket}
        end

      {:error, _} ->
        {:ok, socket |> put_flash(:error, "Game not found.") |> redirect(to: ~p"/")}
    end
  end

  # ── Render (dispatcher) ────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <div id="host-presence" phx-hook="Presence" class="mx-auto max-w-7xl px-4 pb-28">
      <%= case @status do %>
        <% :lobby -> %>
          <.lobby_view
            code={@code}
            game_name={@game_name}
            player_count={@player_count}
            players={@players}
            prizes={@prizes}
            settings={@settings}
          />
        <% status when status in [:running, :paused] -> %>
          <.command_center
            code={@code}
            status={@status}
            picks={@picks}
            prizes={@prizes}
            prize_progress={@prize_progress}
            player_count={@player_count}
            players={@players}
            struck={@struck}
            next_pick_at={@next_pick_at}
            server_now={@server_now}
          />
        <% :finished -> %>
          <.game_over_view
            code={@code}
            prizes={@prizes}
            picks={@picks}
            settings={@settings}
          />
      <% end %>

      <%!-- Floating reactions container --%>
      <div id="floating-reactions" phx-hook="FloatingReaction" class="pointer-events-none fixed inset-0 z-50" />
    </div>
    """
  end

  # ── Lobby View ─────────────────────────────────────────────────────

  attr :code, :string, required: true
  attr :game_name, :string, required: true
  attr :player_count, :integer, required: true
  attr :players, :list, required: true
  attr :prizes, :map, required: true
  attr :settings, :map, required: true

  defp lobby_view(assigns) do
    enabled_prizes = Map.get(assigns.settings, :enabled_prizes, Map.keys(assigns.prizes))
    interval = Map.get(assigns.settings, :interval, 30)
    bogey_limit = Map.get(assigns.settings, :bogey_limit, 3)
    display_players = Enum.take(assigns.players, 20)
    overflow = max(length(assigns.players) - 20, 0)

    assigns =
      assigns
      |> assign(:enabled_prizes, enabled_prizes)
      |> assign(:interval, interval)
      |> assign(:bogey_limit, bogey_limit)
      |> assign(:display_players, display_players)
      |> assign(:overflow, overflow)

    ~H"""
    <div class="flex min-h-[70vh] flex-col items-center justify-center text-center">
      <div class="animate-fade-in-up w-full max-w-lg space-y-6">
        <%!-- Game name --%>
        <div class="space-y-1">
          <h1 class="text-3xl font-bold text-[var(--text-primary)]">
            <%= @game_name %>
          </h1>
          <p class="text-[var(--text-muted)]">Share the code to invite players</p>
        </div>

        <%!-- Game code hero card --%>
        <div
          id="host-lobby-code"
          phx-hook="CopyCode"
          data-code={@code}
          class="cursor-pointer select-all rounded-2xl bg-[var(--elevated)] px-8 py-6 text-center shadow-lg"
        >
          <span class="font-mono text-5xl font-black tracking-widest text-accent">
            <%= @code %>
          </span>
          <p class="mt-2 text-xs text-[var(--text-muted)]">Tap to copy</p>
        </div>

        <%!-- Live player count --%>
        <div class="animate-fade-in-up stagger-2">
          <div class="inline-flex items-center gap-2 rounded-full bg-[var(--surface)] border border px-4 py-2">
            <span class="relative flex h-2.5 w-2.5">
              <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-success opacity-75" />
              <span class="relative inline-flex h-2.5 w-2.5 rounded-full bg-success" />
            </span>
            <span class="text-sm font-semibold text-[var(--text-primary)]">
              <%= @player_count %> player<%= if @player_count != 1, do: "s" %> joined
            </span>
          </div>
        </div>

        <%!-- Player list --%>
        <div :if={@player_count > 0} class="animate-fade-in-up stagger-3">
          <.card>
            <h3 class="mb-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
              Players
            </h3>
            <div class="flex flex-wrap gap-2">
              <span
                :for={{_player_id, idx} <- Enum.with_index(@display_players, 1)}
                class="inline-flex items-center rounded-full bg-[var(--elevated)] px-3 py-1 text-sm font-medium text-[var(--text-secondary)]"
              >
                Player <%= idx %>
              </span>
              <span
                :if={@overflow > 0}
                class="inline-flex items-center rounded-full bg-accent/10 px-3 py-1 text-sm font-semibold text-accent"
              >
                +<%= @overflow %> more
              </span>
            </div>
          </.card>
        </div>

        <%!-- Settings summary --%>
        <div class="animate-fade-in-up stagger-4">
          <.card>
            <h3 class="mb-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
              Settings
            </h3>
            <div class="grid grid-cols-2 gap-3 text-sm">
              <div class="flex items-center gap-2">
                <span class="text-[var(--text-muted)]">Interval</span>
                <span class="font-semibold text-[var(--text-primary)]"><%= @interval %>s</span>
              </div>
              <div class="flex items-center gap-2">
                <span class="text-[var(--text-muted)]">Bogey limit</span>
                <span class="font-semibold text-[var(--text-primary)]"><%= @bogey_limit %></span>
              </div>
            </div>
            <div class="mt-3">
              <p class="mb-1 text-xs text-[var(--text-muted)]">Prizes</p>
              <div class="flex flex-wrap gap-1.5">
                <span
                  :for={prize <- @enabled_prizes}
                  class="inline-flex items-center rounded-full border border px-2.5 py-0.5 text-xs font-medium text-[var(--text-secondary)]"
                >
                  <%= prize_label(prize) %>
                </span>
              </div>
            </div>
          </.card>
        </div>

        <%!-- Start button --%>
        <div class="animate-fade-in-up stagger-5 pt-2">
          <.button
            phx-click="start"
            variant="primary"
            size="lg"
            disabled={@player_count == 0}
            class="w-full"
          >
            <%= if @player_count == 0 do %>
              Waiting for players...
            <% else %>
              Start Game (<%= @player_count %> player<%= if @player_count != 1, do: "s" %>)
            <% end %>
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # ── Command Center (Running / Paused) ──────────────────────────────

  attr :code, :string, required: true
  attr :status, :atom, required: true
  attr :picks, :list, required: true
  attr :prizes, :map, required: true
  attr :prize_progress, :map, required: true
  attr :player_count, :integer, required: true
  attr :players, :list, required: true
  attr :struck, :map, required: true
  attr :next_pick_at, :any, required: true
  attr :server_now, :any, required: true

  defp command_center(assigns) do
    # Build leaderboard: sort players by strike count (desc), take top 20
    leaderboard =
      assigns.struck
      |> Enum.map(fn {player_id, strikes} ->
        strike_count = if is_list(strikes), do: length(strikes), else: 0
        # Determine near-prize status from prize_progress
        player_progress = Map.get(assigns.prize_progress, player_id, %{})

        near_prize =
          Enum.any?(player_progress, fn {prize, {struck, required}} ->
            Map.get(assigns.prizes, prize) == nil and required - struck <= 1
          end)

        total = 15  # Standard Tambola ticket has 15 numbers
        %{
          player_id: player_id,
          strike_count: strike_count,
          total: total,
          near_prize: near_prize
        }
      end)
      |> Enum.sort_by(& &1.strike_count, :desc)
      |> Enum.take(20)

    assigns = assign(assigns, :leaderboard, leaderboard)

    ~H"""
    <%!-- Sticky status bar --%>
    <div class="sticky top-0 z-30 -mx-4 mb-4 border-b border-[var(--border)] bg-[var(--bg)]/95 px-4 py-2 backdrop-blur-sm">
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <span
            id="host-game-code"
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
        <span class="text-xs text-[var(--text-muted)]">
          <%= @player_count %> player<%= if @player_count != 1, do: "s" %>
        </span>
      </div>
    </div>

    <%!-- Three-column layout (desktop), single column (mobile) --%>
    <div class="md:grid md:grid-cols-[280px_1fr_300px] md:gap-6">

      <%!-- Left column: Board + Countdown --%>
      <div class="hidden md:block space-y-4">
        <.card>
          <h3 class="mb-2 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
            Board
          </h3>
          <.board picks={@picks} />
        </.card>

        <div class="flex flex-col items-center gap-2">
          <.countdown_ring
            next_pick_at={@next_pick_at}
            server_now={@server_now}
            status={@status}
          />
          <span class="text-sm font-semibold text-[var(--text-muted)]">
            <%= length(@picks) %>/90 picked
          </span>
        </div>
      </div>

      <%!-- Center column: Controls + Leaderboard + Prizes --%>
      <div class="space-y-4">
        <%!-- Mobile: Countdown + picked count --%>
        <div class="flex items-center justify-center gap-4 md:hidden">
          <.countdown_ring
            next_pick_at={@next_pick_at}
            server_now={@server_now}
            status={@status}
          />
          <span class="text-sm font-semibold text-[var(--text-muted)]">
            <%= length(@picks) %>/90 picked
          </span>
        </div>

        <%!-- Game controls --%>
        <.card>
          <div class="flex items-center justify-center gap-3">
            <%= if @status == :running do %>
              <.button phx-click="pause" variant="secondary" size="md">
                Pause
              </.button>
            <% end %>
            <%= if @status == :paused do %>
              <.button phx-click="resume" variant="primary" size="md">
                Resume
              </.button>
            <% end %>
            <.button
              phx-click="end_game"
              variant="danger"
              size="md"
              data-confirm="End the game? This cannot be undone."
            >
              End Game
            </.button>
          </div>
        </.card>

        <%!-- Player leaderboard --%>
        <.card>
          <h3 class="mb-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
            Leaderboard
          </h3>
          <div :if={@leaderboard == []} class="py-4 text-center text-sm text-[var(--text-muted)]">
            No strikes yet
          </div>
          <div :if={@leaderboard != []} class="space-y-2">
            <div
              :for={{entry, idx} <- Enum.with_index(@leaderboard, 1)}
              class="flex items-center gap-3"
            >
              <span class="w-5 text-right text-xs font-bold text-[var(--text-muted)]">
                <%= idx %>
              </span>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium text-[var(--text-primary)] truncate">
                    Player <%= entry.player_id %>
                  </span>
                  <span
                    :if={entry.near_prize}
                    class="inline-flex items-center rounded-full bg-warning/20 px-1.5 py-0.5 text-[10px] font-bold text-[var(--warning)]"
                    title="Close to winning a prize!"
                  >
                    CLOSE
                  </span>
                </div>
                <div class="mt-1 flex items-center gap-2">
                  <div class="h-1.5 flex-1 rounded-full bg-[var(--elevated)] overflow-hidden">
                    <div
                      class="h-full rounded-full bg-accent transition-all duration-300"
                      style={"width: #{min(entry.strike_count / entry.total * 100, 100)}%"}
                    />
                  </div>
                  <span class="text-xs tabular-nums text-[var(--text-muted)]">
                    <%= entry.strike_count %>/<%= entry.total %>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </.card>

        <%!-- Prize tracker --%>
        <.card>
          <h3 class="mb-3 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
            Prizes
          </h3>
          <div class="space-y-2">
            <div
              :for={{prize, winner} <- @prizes}
              class={[
                "flex items-center justify-between rounded-xl px-3 py-2 border border",
                if(winner, do: "bg-accent/5", else: "bg-[var(--surface)]")
              ]}
            >
              <span class={[
                "text-sm font-semibold",
                if(winner, do: "text-accent", else: "text-[var(--text-primary)]")
              ]}>
                <%= prize_label(prize) %>
              </span>
              <span :if={winner} class="text-xs font-medium text-accent">
                Won by Player <%= winner %>
              </span>
              <.badge :if={!winner} variant="default">
                Unclaimed
              </.badge>
            </div>
          </div>
        </.card>

        <%!-- Mobile: Board (collapsible) --%>
        <div class="md:hidden">
          <.card>
            <h3 class="mb-2 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
              Board
            </h3>
            <.board picks={@picks} />
          </.card>
        </div>
      </div>

      <%!-- Right column (desktop) / below content (mobile): Activity feed --%>
      <div class="mt-4 md:mt-0 md:flex md:flex-col md:h-[calc(100vh-8rem)]">
        <.live_component module={MothWeb.Game.ActivityFeed} id="host-feed" />
      </div>
    </div>

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

  attr :code, :string, required: true
  attr :prizes, :map, required: true
  attr :picks, :list, required: true
  attr :settings, :map, required: true

  defp game_over_view(assigns) do
    winners =
      assigns.prizes
      |> Enum.filter(fn {_prize, winner} -> winner != nil end)
      |> Enum.map(fn {prize, winner_id} ->
        %{prize: prize, label: prize_label(prize), winner_id: winner_id}
      end)

    assigns = assign(assigns, :winners, winners)

    ~H"""
    <div
      id="host-game-over"
      phx-hook="Confetti"
      class="flex min-h-[70vh] flex-col items-center justify-center text-center"
    >
      <div class="animate-scale-in w-full max-w-lg space-y-8">
        <div class="space-y-2">
          <h1 class="text-4xl font-black text-[var(--text-primary)]">
            Game Over
          </h1>
          <p class="text-[var(--text-muted)]">
            <%= length(@picks) %> numbers picked
          </p>
        </div>

        <%!-- Prize winners summary --%>
        <div :if={@winners != []} class="space-y-3">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-[var(--text-muted)]">
            Winners
          </h2>
          <div class="space-y-2">
            <div
              :for={w <- @winners}
              class="flex items-center justify-between rounded-xl bg-[var(--surface)] border border px-4 py-3"
            >
              <span class="font-semibold text-[var(--text-primary)]"><%= w.label %></span>
              <span class="text-sm font-medium text-accent">
                Player <%= w.winner_id %>
              </span>
            </div>
          </div>
        </div>

        <div :if={@winners == []} class="animate-fade-in-up stagger-2">
          <p class="text-[var(--text-muted)]">No prizes were claimed this game.</p>
        </div>

        <%!-- Game stats --%>
        <.card class="text-left">
          <h3 class="mb-2 text-xs font-semibold uppercase tracking-wider text-[var(--text-muted)]">
            Game Stats
          </h3>
          <div class="grid grid-cols-2 gap-3 text-sm">
            <div>
              <span class="text-[var(--text-muted)]">Numbers picked</span>
              <p class="text-lg font-bold text-[var(--text-primary)]"><%= length(@picks) %>/90</p>
            </div>
            <div>
              <span class="text-[var(--text-muted)]">Prizes claimed</span>
              <p class="text-lg font-bold text-[var(--text-primary)]">
                <%= length(@winners) %>/<%= map_size(@prizes) %>
              </p>
            </div>
          </div>
        </.card>

        <%!-- Action buttons --%>
        <div class="animate-fade-in-up stagger-3 flex flex-col gap-3">
          <.button phx-click="play_again" variant="primary" size="lg" class="w-full">
            Play Again
          </.button>
          <.button phx-click="back_home" variant="ghost" size="lg" class="w-full">
            Back to Home
          </.button>
        </div>
      </div>
    </div>
    """
  end

  # ── Event Handlers ─────────────────────────────────────────────────

  def handle_event("start", _params, socket) do
    code = socket.assigns.code
    user_id = socket.assigns.current_user.id
    Game.start_game(code, user_id)

    # Re-fetch state to get tickets and prize_progress
    case Game.game_state(code) do
      {:ok, state} ->
        {:noreply,
         socket
         |> assign(:status, state.status)
         |> assign(:tickets, state[:tickets] || %{})
         |> assign(:struck, state[:struck] || %{})
         |> assign(:prize_progress, state[:prize_progress] || %{})
         |> assign(:players, state.players)
         |> assign(:player_count, length(state.players))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("pause", _params, socket) do
    Game.pause(socket.assigns.code, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("resume", _params, socket) do
    Game.resume(socket.assigns.code, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("end_game", _params, socket) do
    Game.end_game(socket.assigns.code, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("play_again", _params, socket) do
    code = socket.assigns.code
    user_id = socket.assigns.current_user.id

    case Game.clone_game(code, user_id) do
      {:ok, new_code} ->
        {:noreply, push_navigate(socket, to: ~p"/game/#{new_code}/host")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not create a new game.")}
    end
  end

  def handle_event("reaction", %{"emoji" => emoji}, socket) do
    Game.send_reaction(socket.assigns.code, socket.assigns.current_user.id, emoji)
    {:noreply, socket}
  end

  def handle_event("back_home", _params, socket) do
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

    # Update struck map if payload includes it
    socket =
      if payload[:struck] do
        assign(socket, :struck, payload.struck)
      else
        socket
      end

    # Update prize_progress if payload includes it
    socket =
      if payload[:prize_progress] do
        assign(socket, :prize_progress, payload.prize_progress)
      else
        socket
      end

    send_update(MothWeb.Game.ActivityFeed, id: "host-feed", new_entry: %{
      id: System.unique_integer([:positive]),
      type: :pick,
      text: "Number #{payload.number} picked",
      number: payload.number,
      user_name: nil,
      user_id: nil,
      timestamp: DateTime.utc_now()
    })

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

    send_update(MothWeb.Game.ActivityFeed, id: "host-feed", new_entry: %{
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
    send_update(MothWeb.Game.ActivityFeed, id: "host-feed", new_entry: %{
      id: System.unique_integer([:positive]),
      type: :prize_claimed,
      text: prize_label(payload.prize),
      number: nil,
      user_name: "Player #{payload.winner_id}",
      user_id: payload.winner_id,
      timestamp: DateTime.utc_now()
    })

    socket =
      socket
      |> update(:prizes, fn prizes -> Map.put(prizes, payload.prize, payload.winner_id) end)

    {:noreply, socket}
  end

  def handle_info({:bogey, payload}, socket) do
    send_update(MothWeb.Game.ActivityFeed, id: "host-feed", new_entry: %{
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
    send_update(MothWeb.Game.ActivityFeed, id: "host-feed", new_entry: %{
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

  def handle_info({:player_joined, payload}, socket) do
    player_id = payload[:user_id] || payload[:player_id]

    socket =
      socket
      |> update(:player_count, &(&1 + 1))
      |> update(:players, fn players ->
        if player_id && player_id not in players,
          do: players ++ [player_id],
          else: players
      end)

    send_update(MothWeb.Game.ActivityFeed, id: "host-feed", new_entry: %{
      id: System.unique_integer([:positive]),
      type: :system,
      text: "Player #{player_id || "?"} joined",
      number: nil,
      user_name: nil,
      user_id: nil,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  def handle_info({:player_left, payload}, socket) do
    player_id = payload[:user_id] || payload[:player_id]

    socket =
      socket
      |> update(:player_count, &max(&1 - 1, 0))
      |> update(:players, fn players ->
        if player_id, do: List.delete(players, player_id), else: players
      end)

    {:noreply, socket}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :presences, MothWeb.Presence.list_players(socket.assigns.code))}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end

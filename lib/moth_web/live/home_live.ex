defmodule MothWeb.HomeLive do
  use MothWeb, :live_view

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:code, "")
      |> maybe_load_recent_games()

    {:ok, socket}
  end

  defp maybe_load_recent_games(socket) do
    case socket.assigns.current_user do
      nil ->
        assign(socket, :recent_games, nil)

      user ->
        assign_async(socket, :recent_games, fn ->
          {:ok, %{recent_games: Moth.Game.recent_games(user.id)}}
        end)
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center min-h-[80vh] px-4 py-8">
      <%!-- User menu (authenticated) --%>
      <div :if={@current_user} class="absolute top-4 right-4 animate-fade-in-up">
        <div class="relative" phx-click-away={Phoenix.LiveView.JS.hide(to: "#user-dropdown")}>
          <button
            type="button"
            class="flex items-center gap-2 rounded-full px-2 py-1 hover:bg-elevated transition-colors"
            phx-click={Phoenix.LiveView.JS.toggle(to: "#user-dropdown")}
          >
            <.avatar id={@current_user.id} name={@current_user.name} size="sm" />
            <span class="text-sm font-medium text-primary hidden sm:inline">
              <%= @current_user.name %>
            </span>
          </button>
          <div
            id="user-dropdown"
            class="hidden absolute right-0 mt-2 w-48 rounded-xl border bg-[var(--surface)] shadow-lg py-1 z-50"
          >
            <.link
              navigate={~p"/profile"}
              class="block px-4 py-2 text-sm text-primary hover:bg-elevated transition-colors"
            >
              Profile
            </.link>
            <form action={~p"/auth/logout"} method="post">
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
              <button
                type="submit"
                class="block w-full text-left px-4 py-2 text-sm text-primary hover:bg-elevated transition-colors"
              >
                Sign out
              </button>
            </form>
          </div>
        </div>
      </div>

      <%!-- Logo & tagline --%>
      <div class="mt-16 mb-10 text-center animate-fade-in-up stagger-1">
        <h1 class="text-6xl font-bold text-accent tracking-tight">moth</h1>
        <p class="mt-3 text-lg text-muted">Real-time Tambola / Housie</p>
      </div>

      <%!-- Join game form --%>
      <div class="w-full max-w-sm animate-fade-in-up stagger-2">
        <form phx-submit="join_game" class="flex gap-2">
          <input
            type="text"
            name="code"
            value={@code}
            placeholder="Enter game code"
            required
            autocomplete="off"
            class={[
              "flex-1 rounded-xl border bg-[var(--surface)] px-4 py-3 text-lg text-center font-mono uppercase",
              "placeholder:text-muted placeholder:normal-case",
              "focus:border-accent focus:ring-2 focus:ring-accent/20 focus:outline-none",
              "transition-colors duration-150"
            ]}
          />
          <.button variant="primary" size="lg" type="submit">Join</.button>
        </form>
      </div>

      <%!-- Create Game (authenticated) --%>
      <div :if={@current_user} class="mt-6 animate-fade-in-up stagger-3">
        <.link navigate={~p"/game/new"}>
          <.button variant="secondary" size="lg">Create Game</.button>
        </.link>
      </div>

      <%!-- Auth buttons (unauthenticated) --%>
      <div :if={!@current_user} class="mt-8 w-full max-w-sm space-y-3 animate-fade-in-up stagger-3">
        <.link
          href={~p"/auth/google"}
          class="flex items-center justify-center w-full rounded-full border px-6 py-3 text-sm font-semibold text-primary hover:bg-elevated transition-colors"
        >
          Sign in with Google
        </.link>
        <.link
          navigate={~p"/auth/magic"}
          class="flex items-center justify-center w-full rounded-full border px-6 py-3 text-sm font-semibold text-primary hover:bg-elevated transition-colors"
        >
          Sign in with Email
        </.link>
      </div>

      <%!-- Recent games (authenticated) --%>
      <div :if={@current_user} class="mt-10 w-full max-w-md animate-fade-in-up stagger-4">
        <h2 class="text-sm font-semibold text-muted uppercase tracking-wider mb-3">Recent Games</h2>
        <%= case @recent_games do %>
          <% %{loading: true} -> %>
            <div class="space-y-3">
              <.skeleton variant="card" />
              <.skeleton variant="card" />
            </div>
          <% %{ok?: true, result: games} when games != [] -> %>
            <div class="space-y-3">
              <.link :for={game <- games} navigate={~p"/game/#{game.code}"} class="block">
                <.card class="hover:border-accent/50 transition-colors cursor-pointer">
                  <div class="flex items-center justify-between">
                    <div>
                      <p class="font-semibold text-primary"><%= game.name %></p>
                      <p class="text-sm font-mono text-muted mt-0.5"><%= game.code %></p>
                    </div>
                    <div class="flex flex-col items-end gap-1">
                      <.badge variant={game_status_variant(game.status)}>
                        <%= game.status %>
                      </.badge>
                      <span class="text-xs text-muted"><%= relative_time(game.inserted_at) %></span>
                    </div>
                  </div>
                </.card>
              </.link>
            </div>
          <% %{ok?: true, result: _} -> %>
            <.card class="text-center py-8">
              <p class="text-muted">No games yet. Create one to get started!</p>
            </.card>
          <% _ -> %>
            <.card class="text-center py-8">
              <p class="text-muted">Could not load recent games.</p>
            </.card>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("join_game", %{"code" => code}, socket) do
    code = String.upcase(String.trim(code))
    {:noreply, push_navigate(socket, to: ~p"/game/#{code}")}
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp game_status_variant("lobby"), do: "paused"
  defp game_status_variant("running"), do: "live"
  defp game_status_variant("finished"), do: "finished"
  defp game_status_variant(_), do: "default"

  defp relative_time(datetime) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3_600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end
end

defmodule MothWeb.ProfileLive do
  use MothWeb, :live_view

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:editing_name, false)
      |> assign(:theme, "system")
      |> assign_async(:recent_games, fn ->
        {:ok, %{recent_games: Moth.Game.recent_games(user.id)}}
      end)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center min-h-[80vh] px-4 py-8">
      <%!-- Back button --%>
      <div class="absolute top-4 left-4 animate-fade-in-up">
        <.link navigate={~p"/"}>
          <.button variant="ghost" size="sm">
            <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" aria-hidden="true">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" />
            </svg>
            Back
          </.button>
        </.link>
      </div>

      <%!-- Avatar --%>
      <div class="mt-12 mb-6 animate-fade-in-up stagger-1">
        <.avatar id={to_string(@current_user.id)} name={@current_user.name || @current_user.email} size="lg" />
      </div>

      <%!-- Name (editable) --%>
      <div class="mb-1 animate-fade-in-up stagger-2">
        <%= if @editing_name do %>
          <form phx-submit="update_name" class="flex items-center gap-2">
            <input
              type="text"
              name="name"
              value={@current_user.name}
              autofocus
              phx-blur="update_name"
              class={[
                "rounded-xl border bg-[var(--surface)] px-3 py-1.5 text-lg font-bold text-primary text-center",
                "focus:border-accent focus:ring-2 focus:ring-accent/20 focus:outline-none",
                "transition-colors duration-150"
              ]}
            />
          </form>
        <% else %>
          <div class="flex items-center gap-2">
            <h1 class="text-xl font-bold text-primary"><%= @current_user.name || "Anonymous" %></h1>
            <button
              type="button"
              phx-click="toggle_edit_name"
              class="text-muted hover:text-primary transition-colors"
              aria-label="Edit name"
            >
              <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
                <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
              </svg>
            </button>
          </div>
        <% end %>
      </div>

      <%!-- Email --%>
      <p class="text-sm text-muted mb-8 animate-fade-in-up stagger-2"><%= @current_user.email %></p>

      <%!-- Theme control --%>
      <div class="mb-10 animate-fade-in-up stagger-3">
        <p class="text-xs font-semibold text-muted uppercase tracking-wider mb-2 text-center">Theme</p>
        <.segmented_control
          options={[
            %{value: "light", label: "Light"},
            %{value: "dark", label: "Dark"},
            %{value: "system", label: "System"}
          ]}
          selected={@theme}
          name="theme"
          on_select="set_theme"
        />
      </div>

      <%!-- Recent games --%>
      <div class="w-full max-w-md animate-fade-in-up stagger-4">
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

      <%!-- Sign out --%>
      <div class="mt-10 w-full max-w-md animate-fade-in-up stagger-5">
        <form action={~p"/auth/logout"} method="post">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <.button variant="danger" size="md" type="submit" class="w-full">
            Sign out
          </.button>
        </form>
      </div>
    </div>
    """
  end

  def handle_event("toggle_edit_name", _params, socket) do
    {:noreply, assign(socket, editing_name: !socket.assigns.editing_name)}
  end

  def handle_event("update_name", %{"name" => name}, socket) do
    name = String.trim(name)

    if name != "" do
      case Moth.Auth.update_user(socket.assigns.current_user, %{name: name}) do
        {:ok, updated_user} ->
          {:noreply,
           socket
           |> assign(:current_user, updated_user)
           |> assign(:editing_name, false)}

        {:error, _changeset} ->
          {:noreply, assign(socket, editing_name: false)}
      end
    else
      {:noreply, assign(socket, editing_name: false)}
    end
  end

  def handle_event("set_theme", %{"value" => theme}, socket) do
    {:noreply,
     socket
     |> assign(:theme, theme)
     |> push_event("set-theme", %{theme: theme})}
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

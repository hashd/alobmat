defmodule MothWeb.HomeLive do
  use MothWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-[60vh] space-y-8">
      <h1 class="text-4xl font-bold text-gray-900">Moth</h1>
      <p class="text-lg text-gray-600">Real-time Tambola / Housie</p>

      <%= if @current_user do %>
        <div class="space-y-4 text-center">
          <p class="text-gray-700">Welcome, <%= @current_user.name %></p>
          <div class="flex gap-4">
            <.link
              navigate={~p"/game/new"}
              class="rounded-lg bg-indigo-600 px-6 py-3 text-white font-semibold hover:bg-indigo-500"
            >
              Create Game
            </.link>
          </div>
          <form class="mt-4" action={~p"/auth/logout"} method="post">
            <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
            <button type="submit" class="text-sm text-gray-500 hover:text-gray-700">Sign out</button>
          </form>
        </div>
      <% else %>
        <div class="space-y-4 w-full max-w-xs">
          <.link
            navigate={~p"/auth/magic"}
            class="block w-full rounded-lg bg-indigo-600 px-6 py-3 text-center text-white font-semibold hover:bg-indigo-500"
          >
            Sign in with Email
          </.link>
          <.link
            href={~p"/auth/google"}
            class="block w-full rounded-lg border border-gray-300 px-6 py-3 text-center text-gray-700 font-semibold hover:bg-gray-50"
          >
            Sign in with Google
          </.link>
        </div>
      <% end %>

      <div class="mt-8">
        <form phx-submit="join_game" class="flex gap-2">
          <input
            type="text"
            name="code"
            placeholder="Enter game code"
            class="rounded-lg border-gray-300 px-4 py-2 uppercase"
            required
          />
          <button
            type="submit"
            class="rounded-lg bg-green-600 px-4 py-2 text-white font-semibold hover:bg-green-500"
          >
            Join
          </button>
        </form>
      </div>
    </div>
    """
  end

  def handle_event("join_game", %{"code" => code}, socket) do
    code = String.upcase(String.trim(code))
    {:noreply, push_navigate(socket, to: ~p"/game/#{code}")}
  end
end

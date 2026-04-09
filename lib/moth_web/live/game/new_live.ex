defmodule MothWeb.Game.NewLive do
  use MothWeb, :live_view

  alias Moth.Game

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, form: to_form(%{"name" => "", "interval" => "30", "bogey_limit" => "3"}))}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <h1 class="text-2xl font-bold">Create a Game</h1>

      <.form for={@form} phx-submit="create" class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700">Game Name</label>
          <input
            type="text"
            name="name"
            value={@form["name"].value}
            required
            class="mt-1 w-full rounded-lg border-gray-300"
            placeholder="Friday Housie"
          />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700">Pick Interval (seconds)</label>
          <input
            type="number"
            name="interval"
            value={@form["interval"].value}
            min="10"
            max="120"
            class="mt-1 w-full rounded-lg border-gray-300"
          />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700">Bogey Limit</label>
          <input
            type="number"
            name="bogey_limit"
            value={@form["bogey_limit"].value}
            min="1"
            max="10"
            class="mt-1 w-full rounded-lg border-gray-300"
          />
        </div>
        <button
          type="submit"
          class="w-full rounded-lg bg-indigo-600 px-6 py-3 text-white font-semibold hover:bg-indigo-500"
        >
          Create Game
        </button>
      </.form>
    </div>
    """
  end

  def handle_event("create", params, socket) do
    settings = %{
      interval: String.to_integer(params["interval"] || "30"),
      bogey_limit: String.to_integer(params["bogey_limit"] || "3"),
      enabled_prizes: [:early_five, :top_line, :middle_line, :bottom_line, :full_house]
    }

    case Game.create_game(socket.assigns.current_user.id, %{
           name: params["name"],
           settings: settings
         }) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: ~p"/game/#{code}/host")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create game.")}
    end
  end
end

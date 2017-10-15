defmodule MothWeb.GameChannel do
  use Phoenix.Channel
  alias Moth.{Accounts, Housie}
  alias MothWeb.Players
  @max_age 24 * 60 * 60

  def join("game:" <> id, %{"token" => token}, socket) do
    game    = Housie.get_game!(id)
    state   = Housie.game_state(id)

    case Phoenix.Token.verify(socket, "tambola sockets", token, max_age: @max_age) do
      {:ok, user_id} ->
        socket = socket
          |> assign(:game_id, id)
          |> assign(:user, Accounts.get_user!(user_id))

        send(self(), :after_join)
        {:ok, %{game: game, state: state}, socket}
      {:error, _reason} ->
        {:error, %{status: :error, reason: "Invalid token, try logging in again"}}
    end
  end
  def join("game:" <> id, _params, socket) do
    socket  = assign(socket, :game_id, id)
    game    = Housie.get_game!(id)
    state   = Housie.game_state(id)

    {:ok, %{game: game, state: state}, assign(socket, :user, nil)}
  end

  def handle_in("message", %{"text" => text}, %{assigns: %{user: user}} = socket) do
    case user do
      nil   -> {:noreply, socket}
      _     ->
        broadcast! socket, "message", %{text: text, user: user}
        {:noreply, socket}
    end
  end
  def handle_in("message", _params, socket) do
    {:noreply, socket}
  end

  def handle_in("notification", %{"type" => "pause"} = params, socket) do
    if socket.assigns.user do
      broadcast! socket, "pause", %{}
      broadcast! socket, "notification", Map.put(params, :user, socket.assigns.user)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

#  def handle_out("message", payload, socket) do
#    push socket, "message", payload
#    {:noreply, socket}
#  end

  def handle_info(:after_join, %{assigns: %{user: user}} = socket) do
    push socket, "presence", Players.list(socket)
    {:ok, _} = Players.track(socket, user.id, %{
      online_at: inspect(System.system_time(:seconds))
    })
    {:noreply, socket}
  end
end
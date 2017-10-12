defmodule MothWeb.GameChannel do
  use Phoenix.Channel
  alias Moth.{Accounts, Housie}
  @max_age 2 * 7 * 24 * 60 * 60

  def join("game:" <> id, %{"token" => token}, socket) do
    socket = assign(socket, :game_id, id)
    games  = Housie.list_running_games
    case Phoenix.Token.verify(socket, "tambola sockets", token, max_age: @max_age) do
      {:ok, user_id} ->
        user = Accounts.get_user!(user_id)
        {:ok, %{games: games}, assign(socket, :user, user)}
      {:error, _reason} ->
        {:ok, %{games: games}, assign(socket, :user, nil)}
    end
  end
  def join("game:" <> id, _params, socket) do
    {:ok, assign(socket, :user, nil)}
  end

  def handle_in("message", %{"text" => text}, socket) do
    broadcast! socket, "message", %{text: text}
    {:noreply, socket}
  end

  def handle_out("message", payload, socket) do
    push socket, "message", payload
    {:noreply, socket}
  end
end
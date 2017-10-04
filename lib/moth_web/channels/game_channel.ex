defmodule MothWeb.GameChannel do
  use Phoenix.Channel

  def join("game:" <> id, _message, socket) do
    socket |> assign(:id, id)
    {:ok, socket}
  end

  def handle_in("message", %{"body" => body}, socket) do
    broadcast! socket, "new_message", %{body: body}
    {:noreply, socket}
  end

  def handle_out("new_message", payload, socket) do
    push socket, "new_message", payload
    {:noreply, socket}
  end
end
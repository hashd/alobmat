defmodule MothWeb.GameSocket do
  use Phoenix.Socket

  alias Moth.Auth

  channel "game:*", MothWeb.GameChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Auth.get_user_by_api_token(token) do
      {:ok, user} -> {:ok, assign(socket, :current_user, user)}
      :error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end

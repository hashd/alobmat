defmodule MothWeb.UserSocket do
  @moduledoc "Phoenix Socket authenticating Vue SPA clients via API bearer tokens."

  use Phoenix.Socket

  channel "game:*", MothWeb.GameChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Moth.Auth.get_user_by_api_token(token) do
      {:ok, user} -> {:ok, assign(socket, :current_user, user)}
      :error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end

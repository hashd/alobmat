defmodule MothWeb.API.AuthController do
  use MothWeb, :controller

  def token(%{assigns: %{user: user}} = conn, _params) do
    token = Phoenix.Token.sign(conn, "tambola sockets", user.id)

    json conn, %{status: :ok, user_token: token}
  end
  def token(conn, _params) do
    json conn, %{status: :error, reason: "Not authorized"}
  end
end
defmodule MothWeb.API.AuthController do
  use MothWeb, :controller

  def token(%{assigns: %{user: user}} = conn, _params) do
    token = Phoenix.Token.sign(conn, "tambola sockets", user.id)

    json conn, %{status: :ok, user_token: token}
  end
  def token(conn, _params) do
    json conn, %{status: :error, reason: "Not authorized"}
  end

  def about_user(conn, _params) do
    json conn, conn.assigns.user || %{status: :error, reason: "No User Authenticated."}
  end
end
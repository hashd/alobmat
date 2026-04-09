defmodule MothWeb.API.AuthController do
  use MothWeb, :controller

  alias Moth.Auth
  alias Moth.Auth.UserNotifier

  def request_magic_link(conn, %{"email" => email}) do
    email = String.downcase(String.trim(email))
    {token, _} = Auth.build_magic_link_token(email)
    url = url(~p"/auth/magic/verify?token=#{token}")
    UserNotifier.deliver_magic_link(email, url)
    json(conn, %{status: "ok", message: "Magic link sent"})
  end

  def verify_magic_link(conn, %{"token" => token}) do
    case Auth.verify_magic_link(token) do
      {:ok, user} ->
        {api_token, _} = Auth.generate_api_token(user)
        json(conn, %{token: api_token, user: user})

      :error ->
        conn
        |> put_status(401)
        |> json(%{error: %{code: "invalid_token", message: "Invalid or expired token"}})
    end
  end

  def refresh(conn, _params) do
    user = conn.assigns.current_user

    if user do
      {api_token, _} = Auth.generate_api_token(user)
      json(conn, %{token: api_token, user: user})
    else
      conn |> put_status(401) |> json(%{error: %{code: "unauthorized", message: "Invalid token"}})
    end
  end

  def logout(conn, _params) do
    json(conn, %{status: "ok"})
  end
end

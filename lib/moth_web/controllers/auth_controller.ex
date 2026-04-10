defmodule MothWeb.AuthController do
  use MothWeb, :controller

  alias Moth.Auth
  alias MothWeb.Plugs.Auth, as: AuthPlug

  plug Ueberauth

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    user_info = %{
      email: auth.info.email,
      name: auth.info.name || auth.info.email,
      avatar_url: auth.info.image,
      uid: auth.uid
    }

    case Auth.authenticate_oauth(auth.provider, user_info) do
      {:ok, user} ->
        conn
        |> AuthPlug.log_in_user(user)
        |> put_flash(:info, "Welcome, #{user.name}!")
        |> redirect_after_login()

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Authentication failed.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed.")
    |> redirect(to: ~p"/")
  end

  def verify_magic_link(conn, %{"token" => token}) do
    case Auth.verify_magic_link(token) do
      {:ok, user} ->
        conn
        |> AuthPlug.log_in_user(user)
        |> put_flash(:info, "Welcome, #{user.name}!")
        |> redirect_after_login()

      :error ->
        conn
        |> put_flash(:error, "Invalid or expired link. Please request a new one.")
        |> redirect(to: ~p"/auth/magic")
    end
  end

  def logout(conn, _params) do
    AuthPlug.log_out_user(conn)
  end

  defp redirect_after_login(conn) do
    return_to = get_session(conn, :return_to)
    conn = delete_session(conn, :return_to)
    redirect(conn, to: return_to || "/")
  end
end

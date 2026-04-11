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
        {token, _} = Auth.generate_api_token(user)
        redirect(conn, to: "/#/auth/callback?token=#{token}")

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
        {api_token, _} = Auth.generate_api_token(user)
        redirect(conn, to: "/#/auth/callback?token=#{api_token}")

      :error ->
        redirect(conn, to: "/#/auth?error=invalid_link")
    end
  end

  def logout(conn, _params) do
    AuthPlug.log_out_user(conn)
  end

end

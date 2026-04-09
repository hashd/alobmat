defmodule MothWeb.AuthController do
  require Logger
  use MothWeb, :controller

  plug Ueberauth

  alias Moth.{Repo, Accounts}
  alias Moth.Accounts.{Credential, User}

  def log_out(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => "google"} = _params) do
    domain = auth.info.email |> String.split("@") |> List.last
    redirect_url = Map.get(conn.cookies, "ui_redirect_url")
    hosted_domains = Application.get_env(:moth, MothWeb.Auth)[:allowed_hds] || []

    if Enum.any?(hosted_domains, fn s -> s == domain end) do
      case create_or_update_user(auth, "google") do
        {:ok, user} ->
          conn
          |> put_session(:user_id, user.id)
          |> put_flash(:info, "Welcome back!")
          |> redirect(external: redirect_url || ~p"/")
        {:error, reason} ->
          conn
          |> put_flash(:error, reason)
          |> redirect(external: redirect_url || ~p"/")
      end
    else
      conn
      |> put_flash(:error, "Unsupported hosted domain for Google auth")
      |> redirect(to: ~p"/")
    end
  end
  def callback(%{assigns: %{ueberauth_auth: _a}} = conn, %{"provider" => provider} = _params) do
    conn
    |> put_flash(:error, "Unsupported provider #{provider}")
    |> redirect(to: ~p"/")
  end

  defp create_or_update_user(%{credentials: %{token: token}, uid: google_id} = auth, provider) do
    %{name: name, email: email, image: avatar_url} = auth.info

    case Repo.get_by(User, email: email) do
      nil -> get_user(name, google_id, avatar_url, email, provider, token)
      user -> user
    end
    |> Accounts.change_user()
    |> Repo.insert_or_update()
  end

  defp get_user(name, google_id, avatar_url, email, provider, token) do
    %User{name: name, google_id: google_id, avatar_url: avatar_url, email: email, credential: get_credential(email, provider, token)}
  end

  defp get_credential(email, provider, token) do
    %Credential{email: email, provider: provider, token: token}
  end
end

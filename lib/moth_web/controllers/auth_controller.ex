defmodule MothWeb.AuthController do
  require Logger
  use MothWeb, :controller
  @hosted_domains       Application.get_env(:moth, MothWeb.Auth)[:allowed_hds]

  plug Ueberauth

  alias Moth.{Repo, Accounts}
  alias Moth.Accounts.{Credential, User}

  # def request(conn, _params) do 
  #   IO.inspect conn
  #   Ueberauth.Strategy.Google.handle_request!(conn)
  # end

  def log_out(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: base_path(conn, :index))
  end

  # def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
  #   # This callback is called when the user denies the app to get the data from the oauth provider
  #   conn
  #   |> put_status(401)
  #   |> json(%{status: :error, reason: 'Not authorized or necessary permissions not granted.'})
  # end
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => "google"} = _params) do
    domain = auth.info.email |> String.split("@") |> List.last
    
    if Enum.any?(@hosted_domains, fn s -> s == domain end) do
      case create_or_update_user(auth, "google") do
        {:ok, user}  -> 
          conn
          |> put_session(:user_id, user.id)
          |> put_flash(:info, "Welcome back!")
          |> redirect(to: base_path(conn, :index))
        {:error, reason} ->
          conn
          |> put_flash(:error, reason)
          |> redirect(to: base_path(conn, :index))
      end
    else
      conn
      |> put_flash(:error, "Unsupported hosted domain for Google auth")
      |> redirect(to: base_path(conn, :index))
    end
  end
  def callback(%{assigns: %{ueberauth_auth: _a}} = conn, %{"provider" => provider} = _params) do
    conn
    |> put_flash(:error, "Unsupported provider #{provider}")
    |> redirect(to: base_path(conn, :index))
  end

  defp create_or_update_user(%{credentials: %{token: token}, uid: google_id} = auth, provider) do
    %{name: name, email: email, image: avatar_url} = auth.info

    case Repo.get_by(User, email: email) do
      nil   -> get_user(name, google_id, avatar_url, email, provider, token)
      user  -> user
    end
    |> Accounts.change_user()
    |> Repo.insert_or_update
  end

  defp get_user(name, google_id, avatar_url, email, provider, token) do
    %User{name: name, google_id: google_id, avatar_url: avatar_url, email: email, credential: get_credential(email, provider, token)}
  end

  defp get_credential(email, provider, token) do
    %Credential{email: email, provider: provider, token: token}
  end
end
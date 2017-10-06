defmodule MothWeb.API.AuthController do
  use MothWeb, :controller
  plug Ueberauth

  alias MothWeb.UserFromAuth

  def request(conn, _p) do 
    conn
  end

  def log_out(conn, _params) do
    conn
    |> put_status(200)
    |> Guardian.Plug.sign_out
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    # This callback is called when the user denies the app to get the data from the oauth provider
    conn
    |> put_status(401)
    |> json(%{status: :error, reason: 'Not authorized or necessary permissions not granted.'})
  end
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case UserFromAuth.find_or_create(auth) do
      {:ok, user} ->
        conn
        |> put_session(:current_user, user)
        |> json(%{user: user})
      {:error} ->
        conn
        |> put_status(401)
        |> json(%{error: "Authorization failure."})
    end
  end

end
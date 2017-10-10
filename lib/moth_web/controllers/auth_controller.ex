defmodule MothWeb.AuthController do
  use MothWeb, :controller

  plug Ueberauth

  alias Ueberauth.Strategy.Helpers

  # def request(conn, _params) do 
  #   IO.inspect conn
  #   Ueberauth.Strategy.Google.handle_request!(conn)
  # end

  def log_out(conn, _params) do
    conn
    |> put_status(200)
    |> configure_session(drop: true)
  end

  # def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
  #   # This callback is called when the user denies the app to get the data from the oauth provider
  #   conn
  #   |> put_status(401)
  #   |> json(%{status: :error, reason: 'Not authorized or necessary permissions not granted.'})
  # end
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case auth.info.email do
      nil -> conn |> redirect(to: base_path(conn, :index))
      _   ->
        conn
        |> Moth.Guardian.Plug.sign_in(auth.info.email)
        |> redirect(to: base_path(conn, :index))
    end
  end
end
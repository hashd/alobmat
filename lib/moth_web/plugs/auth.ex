defmodule MothWeb.Plugs.Auth do
  @moduledoc "Session-based auth plug for web routes."
  import Plug.Conn
  import Phoenix.Controller

  alias Moth.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    if user_token = get_session(conn, :user_token) do
      user = Auth.get_user_by_session_token(user_token)
      assign(conn, :current_user, user)
    else
      assign(conn, :current_user, nil)
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_session(:return_to, conn.request_path)
      |> put_flash(:error, "You must sign in to access this page.")
      |> redirect(to: "/")
      |> halt()
    end
  end

  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: "/")
      |> halt()
    else
      conn
    end
  end

  def log_in_user(conn, user) do
    token = Auth.generate_user_session_token(user)
    return_to = get_session(conn, :return_to)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_session(:return_to, return_to)
    |> assign(:current_user, user)
  end

  def log_out_user(conn) do
    if user_token = get_session(conn, :user_token) do
      Auth.delete_session_token(user_token)
    end

    conn
    |> renew_session()
    |> redirect(to: "/")
  end

  defp renew_session(conn) do
    clear_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp clear_csrf_token do
    if function_exported?(Plug.CSRFProtection, :delete_csrf_token, 0) do
      Plug.CSRFProtection.delete_csrf_token()
    end
  end
end

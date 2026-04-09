defmodule MothWeb.Plugs.APIAuth do
  @moduledoc "Bearer token auth plug for API routes."
  import Plug.Conn
  import Phoenix.Controller

  alias Moth.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Auth.get_user_by_api_token(token) do
      assign(conn, :current_user, user)
    else
      _ -> assign(conn, :current_user, nil)
    end
  end

  def require_api_auth(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(401)
      |> json(%{error: %{code: "unauthorized", message: "Invalid or missing token"}})
      |> halt()
    end
  end
end

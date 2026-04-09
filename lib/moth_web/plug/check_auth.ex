defmodule MothWeb.Plug.CheckAuth do
  import Plug.Conn
  import Phoenix.Controller

  use MothWeb, :verified_routes

  def init(_params) do
  end

  def call(conn, _params) do
    if conn.assigns[:user] do
      conn
    else
      conn
      |> put_status(401)
      |> redirect(to: ~p"/")
      |> halt()
    end
  end
end

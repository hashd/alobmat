defmodule MothWeb.Plug.CheckAuth do
  import Plug.Conn
  import Phoenix.Controller

  alias MothWeb.Router.Helpers

  def init(_params) do

  end

  def call(conn, _params) do
    if conn.assigns[:user] do
      conn
    else
      conn
      |> put_status(401)
      |> redirect(to: Helpers.base_path(conn, :index))
      |> halt()
    end
  end
end

defmodule MothWeb.Plug.CheckAPIAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(_params) do

  end

  def call(conn, _params) do
    if conn.assigns[:user] do
      conn
    else
      conn
      |> put_status(401)
      |> json(%{status: :error, reason: "You are not authorized to access the resource"})
      |> halt()
    end
  end
end
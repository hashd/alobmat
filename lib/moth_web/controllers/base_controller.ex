defmodule MothWeb.BaseController do
  use MothWeb, :controller

  plug :put_user_assign

  def index(conn, _params) do
    render(conn, :index)
  end

  defp put_user_assign(conn, _opts) do
    assign(conn, :user, conn.assigns[:user])
  end
end

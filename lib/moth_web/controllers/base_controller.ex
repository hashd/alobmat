defmodule MothWeb.BaseController do
  use MothWeb, :controller

  def index(conn, _params) do
    IO.inspect get_session(conn, :email)
    render conn, "index.html"
  end

  def not_found(conn, _params) do
    render conn, "404.html"
  end
end

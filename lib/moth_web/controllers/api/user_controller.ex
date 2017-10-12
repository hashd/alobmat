defmodule MothWeb.API.UserController do
  use MothWeb, :controller

  def index(conn, _params) do
    json conn, %{users: Moth.Accounts.list_users}
  end
end
defmodule MothWeb.Plug.SetUser do
  import Plug.Conn
  # import Phoenix.Controller

  alias Moth.Repo
  alias Moth.Accounts.User

  def init(_params) do
  end

  def call(conn, _params) do
    user_id = get_session(conn, :user_id)
    cond do
      user = user_id && Repo.get(User, user_id) ->
        assign(conn, :user, user)
      true ->
        assign(conn, :user, nil)
    end
  end
end
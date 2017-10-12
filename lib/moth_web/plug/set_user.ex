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
        put_current_user(conn, user)
      true ->
        assign(conn, :user, nil)
    end
  end

  def put_current_user(conn, user) do
    token = Phoenix.Token.sign(conn, "tambola sockets", user.id)

    conn
    |> assign(:user, user)
    |> assign(:token, token)
  end
end
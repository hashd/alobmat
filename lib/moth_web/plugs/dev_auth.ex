defmodule MothWeb.Plugs.DevAuth do
  @moduledoc """
  Dev-only plug that auto-logs in a guest user so you can host/join games
  without going through the auth flow. Inserted into the browser pipeline
  only when `config :moth, dev_routes: true`.
  """
  import Plug.Conn

  alias Moth.Auth
  alias Moth.Auth.User
  alias Moth.Repo

  @dev_email "dev@localhost"

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :user_token) do
      conn
    else
      user = get_or_create_dev_user()
      token = Auth.generate_user_session_token(user)

      conn
      |> put_session(:user_token, token)
      |> assign(:current_user, user)
    end
  end

  defp get_or_create_dev_user do
    case Repo.get_by(User, email: @dev_email) do
      %User{} = user ->
        user

      nil ->
        {:ok, user} = Auth.register(%{email: @dev_email, name: "Dev User"})
        user
    end
  end
end

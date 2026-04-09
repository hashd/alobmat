defmodule MothWeb.LiveAuth do
  import Phoenix.LiveView
  import Phoenix.Component

  alias Moth.Auth

  def on_mount(:default, _params, session, socket) do
    user =
      case session["user_token"] do
        nil -> nil
        token -> Auth.get_user_by_session_token(token)
      end

    {:cont, assign(socket, :current_user, user)}
  end

  def on_mount(:require_auth, _params, session, socket) do
    case session["user_token"] do
      nil ->
        {:halt, redirect(socket, to: "/")}

      token ->
        case Auth.get_user_by_session_token(token) do
          nil -> {:halt, redirect(socket, to: "/")}
          user -> {:cont, assign(socket, :current_user, user)}
        end
    end
  end
end

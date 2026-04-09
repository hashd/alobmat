defmodule MothWeb.API.UserController do
  use MothWeb, :controller

  alias Moth.Auth

  def show(conn, _params) do
    json(conn, %{user: conn.assigns.current_user})
  end

  def update(conn, params) do
    user = conn.assigns.current_user
    attrs = Map.take(params, ["name", "avatar_url"])

    case Auth.update_user(user, attrs) do
      {:ok, user} ->
        json(conn, %{user: user})

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "validation_error", details: changeset_errors(changeset)}})
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

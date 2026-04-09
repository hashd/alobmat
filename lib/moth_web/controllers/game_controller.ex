defmodule MothWeb.GameController do
  use MothWeb, :controller

  def index(conn, %{"id" => id} = _params) do
    conn
    |> assign(:game_id, id)
    |> render(:index)
  end
end

defmodule MothWeb.GameController do
  use MothWeb, :controller

  def index(conn, %{"id" => id} = _params) do
    conn
    |> assign(:game_id, id)
    |> render("index.html")
  end
end

defmodule MothWeb.API.GameController do
  use MothWeb, :controller
  alias Moth.{GameServer, Games}

  def new(conn, %{"id" => id, "interval" => interval} = _params) when is_binary interval do
    json conn, create_new_game(id, interval |> String.to_integer)
  end
  def new(conn, %{"id" => id, "interval" => interval} = _params) when is_integer interval do
    json conn, create_new_game(id, interval)
  end
  def new(conn, %{"id" => id} = _params) do
    json conn, create_new_game(id, 45)
  end

  def show(conn, %{"id" => id}) do
    json conn, Registry.lookup(Games, id) |> List.first |> elem(1) |> GameServer.state
  end

  defp create_new_game(id, interval) do
    case Moth.Housie.start(id, interval) do
      {:ok, _gs}       -> %{status: :ok, game_id: id, interval: interval}
      {:error, reason} -> %{status: :error, reason: reason}
    end
  end
end
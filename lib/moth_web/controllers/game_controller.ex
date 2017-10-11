defmodule MothWeb.GameController do
  use MothWeb, :controller

  alias Moth.Accounts

  def index(conn, %{"id" => id} = _params) do
    conn
    |> assign(:game_id, id)
    |> render("index.html")
  end
end

defmodule MothWeb.API.GameController do
  use MothWeb, :controller
  alias Moth.{Housie.Server, Games}

  def new(conn, %{"name" => name, "interval" => interval} = _params) when is_binary interval do
    json conn, create_new_game(name, interval |> String.to_integer, conn.assigns.user)
  end
  def new(conn, %{"name" => name, "interval" => interval} = _params) when is_integer interval do
    json conn, create_new_game(name, interval, conn.assigns.user)
  end
  def new(conn, %{"name" => name} = _params) do
    json conn, create_new_game(name, 45, conn.assigns.user)
  end

  def show(conn, %{"id" => id}) do
    json conn, Registry.lookup(Games, id) |> List.first |> elem(1) |> Server.state
  end

  defp create_new_game(name, interval, user) do
    game = %Moth.Housie.Game{name: name, details: %{interval: interval, bulletin: ""}, owner: user, prizes: [], moderators: []}

    Ecto.build_assoc(game, :owner)
    case Moth.Housie.start_game(game) do
      {:ok, game}      -> %{status: :ok, game_id: game.id, interval: interval}
      {:error, reason} -> %{status: :error, reason: reason}
    end
  end
end
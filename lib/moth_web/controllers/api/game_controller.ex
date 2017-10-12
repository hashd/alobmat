defmodule MothWeb.API.GameController do
  require Logger
  use MothWeb, :controller
  alias Moth.{Housie, Housie.Server, Games}

  def new(conn, %{"name" => name, "interval" => interval} = params) when is_binary interval do
    json conn, create_new_game(name, interval |> String.to_integer, conn.assigns.user, params["bulletin"])
  end
  def new(conn, %{"name" => name, "interval" => interval} = params) when is_integer interval do
    json conn, create_new_game(name, interval, conn.assigns.user, params["bulletin"])
  end
  def new(conn, %{"name" => name} = params) do
    json conn, create_new_game(name, 45, conn.assigns.user, params["bulletin"])
  end

  def show(conn, %{"id" => id}) when is_binary id do
    show(conn, %{"id" => String.to_integer(id)})
  end
  def show(conn, %{"id" => id}) when is_integer id do 
    case Registry.lookup(Games, id) do
      []                  -> json conn, %{error: :error, reason: "No game found for id: #{id}"}
      [{ p, _n} | []]     -> 
        Logger.log :info, "Trying to prepare state of the server"
        json conn, Server.state(p)
      [{_p, _n} | _r] = l -> 
        Logger.log :info, "Multiple games found with #{id}: #{[l]}"
        json conn, l
    end
  end

  defp create_new_game(name, interval, user, bulletin) do
    game = %{name: name, details: %{interval: interval, bulletin: bulletin}, owner_id: user.id, prizes: [], moderators: []}

    case Housie.start_game(game) do
      {:ok, game}      -> 
        Ecto.build_assoc(game, :owner)
        %{status: :ok, game_id: game.id, interval: interval}
      {:error, reason} -> %{status: :error, reason: reason}
    end
  end
end
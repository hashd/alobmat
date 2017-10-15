defmodule MothWeb.API.GameController do
  require Logger
  use MothWeb, :controller
  alias Moth.{Housie, Housie.Server, Games}

  def index(conn, _params) do
    json conn, %{games: Housie.list_running_games()}
  end

  def new(conn, %{"name" => name, "interval" => interval} = params) when is_binary interval do
    json conn, create_new_game(name, interval |> String.to_integer, conn.assigns.user, params["bulletin"], params["moderators"])
  end
  def new(conn, %{"name" => name, "interval" => interval} = params) when is_integer interval do
    json conn, create_new_game(name, interval, conn.assigns.user, params["bulletin"], params["moderators"])
  end
  def new(conn, %{"name" => name} = params) do
    json conn, create_new_game(name, 45, conn.assigns.user, params["bulletin"], params["moderators"])
  end

  def show(conn, %{"id" => id}) when is_binary id do
    json conn, invoke_action(id, fn p -> Server.state(p) end)
  end

  def pause(conn, %{"id" => id}) when is_binary id do
    case is_admin?(conn.assigns.user, id) do
      true  ->
        json conn, invoke_action(id, fn p -> Server.pause(p) end)
      _     ->
        json conn, %{error: :error, reason: "User is not authorized"}
    end
  end

  def resume(conn, %{"id" => id}) when is_binary id do
    case is_admin?(conn.assigns.user, id) do
      true  ->
        json conn, invoke_action(id, fn p -> Server.resume(p) end)
      _     ->
        json conn, %{error: :error, reason: "User is not authorized"}
    end
  end


  #-----------------PRIVATE FUNCTIONS--------------------------------

  defp create_new_game(name, interval, user, bulletin, moderators) do
    game = %{name: name, details: %{interval: interval, bulletin: bulletin}, owner_id: user.id, prizes: [], moderators: moderators}

    case Housie.start_game(game) do
      {:ok, g}          -> %{status: :ok, game: Map.put(game, :id, g.id)}
      {:error, reason}  -> %{status: :error, reason: reason}
    end
  end

  defp is_admin?(user, game_id) do
    game_id
    |> Housie.get_game_admins!()
    |> Enum.any?(fn u -> u.id == user.id end)
  end

  defp invoke_action(game_id, func) do
    case Registry.lookup(Games, game_id) do
      []                  -> %{error: :error, reason: "No game found for id: #{game_id}"}
      [{ p, _n} | []]     ->
        func.(p)
      [{p, _n} | _r] = l ->
        Logger.log :info, "Multiple games found with #{game_id}: #{[l]}"
        func.(p)
    end
  end
end
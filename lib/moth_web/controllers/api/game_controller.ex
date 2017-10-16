defmodule MothWeb.API.GameController do
  require Logger
  use MothWeb, :controller
  alias Moth.{Housie, Housie.Server, Games}

  def index(conn, _params) do
    games = Housie.list_running_games()
      |> Enum.map(fn g -> Map.put(g, :prizes, []) end)
      |> Enum.map(fn g -> Map.put(g, :moderators, []) end)

    presence = Enum.reduce(games, %{}, fn g, acc ->
      Map.put(acc, g.id, Enum.count(MothWeb.Players.list("game:#{g.id}")))
    end)

    json conn, %{games: games, presence: presence}
  end

  def new(conn, %{"interval" => interval} = params) when is_binary interval do
    new(conn, params |> Map.put("interval", String.to_integer(interval)))
  end
  def new(conn, %{"name" => _n, "interval" => interval} = params) when is_integer interval do
    json conn, create_new_game(params, conn.assigns.user)
  end
  def new(conn, params) do
    new(conn, params |> Map.put("interval", 45))
  end

  def show(conn, %{"id" => id}) when is_binary id do
    game = Housie.get_game!(id)
    case Registry.lookup(Games, id) do
      []              -> json conn, game
      [{p, _v} | _r]  -> json conn, Map.put(game, :server, Server.state(p))
    end
  end

  def pause(conn, %{"id" => id}) when is_binary id do
    case is_admin?(conn.assigns.user, id) do
      true  ->
        json conn, invoke_action(id, fn p ->
          if Server.is_running?(p) do
            MothWeb.Endpoint.broadcast! "game:#{id}", "pause", %{user: conn.assigns.user}
            Server.pause(p)
          else
            %{status: :error, reason: "Game is not currently running"}
          end
        end)
      _     ->
        json conn, %{error: :error, reason: "User is not authorized"}
    end
  end

  def resume(conn, %{"id" => id}) when is_binary id do
    case is_admin?(conn.assigns.user, id) do
      true  ->
        json conn, invoke_action(id, fn p ->
          if Server.is_paused?(p) do
            MothWeb.Endpoint.broadcast! "game:#{id}", "resume", %{user: conn.assigns.user}
            Server.resume(p)
          else
            %{status: :error, reason: "Game is not currently paused"}
          end
        end)
      _     ->
        json conn, %{error: :error, reason: "User is not authorized"}
    end
  end

  def award(conn, %{"game_id" => game_id, "prize_id" => prize_id, "user_id" => user_id}) do
    case is_admin?(conn.assigns.user, game_id) do
      true  ->
        case Housie.update_prize(Housie.get_prize!(prize_id), %{winner_user_id: user_id}) do
          {:ok, prize} ->
            prize = Moth.Repo.preload(prize, :winner)
            MothWeb.Endpoint.broadcast! "game:#{game_id}", "prize_awarded", %{prize: prize, awardee: conn.assigns.user}
            json conn, prize
          {:error, reason} ->
            json conn, %{status: :error, reason: reason}
        end
      _     -> json conn, %{status: :error, reason: "User is not authorized"}
    end
  end


  #-----------------PRIVATE FUNCTIONS--------------------------------
  defp create_new_game(%{
    "name" => name,
    "interval" => interval,
    "about" => about,
    "bulletin" => bulletin,
    "moderators" => moderators,
    "prizes" => prizes
  } = _p, user) do
    prizes = prizes || []
    game = %{name: name, details: %{interval: interval, bulletin: bulletin, about: about}, owner_id: user.id, prizes: [], moderators: moderators}

    case Housie.start_game(game) do
      {:ok, g}          ->
        prizes
        |> Enum.map(fn prize ->
          Ecto.build_assoc(g, :prizes, %{name: prize["name"], reward: prize["reward"]})
        end)
        |> Enum.each(fn prize -> Moth.Repo.insert!(prize) end)

        %{status: :ok, game: Map.put(game, :id, g.id)}
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
defmodule MothWeb.API.GameController do
  use MothWeb, :controller

  alias Moth.Game

  def recent(conn, _params) do
    games = Game.recent_games(conn.assigns.current_user.id, 10)
    json(conn, %{games: games})
  end

  def public_games(conn, _params) do
    games = Game.list_public_games()
    json(conn, %{games: games})
  end

  def clone(conn, %{"code" => code}) do
    case Game.clone_game(String.upcase(code), conn.assigns.current_user.id) do
      {:ok, new_code} -> conn |> put_status(201) |> json(%{code: new_code})
      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: %{code: to_string(reason), message: "Clone failed"}})
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    valid_prizes = ~w(early_five top_line middle_line bottom_line full_house)
    enabled_prizes = case params["enabled_prizes"] do
      list when is_list(list) ->
        list
        |> Enum.filter(&(&1 in valid_prizes))
        |> Enum.map(&String.to_existing_atom/1)
      _ ->
        [:early_five, :top_line, :middle_line, :bottom_line, :full_house]
    end

    settings = %{
      interval: params["interval"] || 30,
      bogey_limit: params["bogey_limit"] || 3,
      enabled_prizes: enabled_prizes,
      visibility: params["visibility"] || "public",
      join_secret: params["join_secret"]
    }

    case Game.create_game(user.id, %{name: params["name"] || "Untitled", settings: settings}) do
      {:ok, code} ->
        conn |> put_status(201) |> json(%{code: code})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "create_failed", message: inspect(reason)}})
    end
  end

  def show(conn, %{"code" => code}) do
    case Game.game_state(String.upcase(code)) do
      {:ok, state} ->
        json(conn, %{game: state})

      {:error, :game_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "not_found", message: "Game not found"}})

      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "unavailable", message: "Game temporarily unavailable"}})
    end
  end

  def join(conn, %{"code" => code} = params) do
    secret = params["secret"]
    case Game.join_game(String.upcase(code), conn.assigns.current_user.id, secret) do
      {:ok, tickets} when is_list(tickets) ->
        json(conn, %{tickets: Enum.map(tickets, &Moth.Game.Ticket.to_map/1)})

      {:ok, ticket} ->
        json(conn, %{ticket: Moth.Game.Ticket.to_map(ticket)})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: to_string(reason), message: "Cannot join"}})
    end
  end

  def start(conn, %{"code" => code}) do
    handle_host_action(conn, code, &Game.start_game/2)
  end

  def pause(conn, %{"code" => code}) do
    handle_host_action(conn, code, &Game.pause/2)
  end

  def resume(conn, %{"code" => code}) do
    handle_host_action(conn, code, &Game.resume/2)
  end

  def end_game(conn, %{"code" => code}) do
    handle_host_action(conn, code, &Game.end_game/2)
  end

  def strike_out(conn, %{"code" => code, "number" => number}) do
    case Game.strike_out(String.upcase(code), conn.assigns.current_user.id, number) do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: to_string(reason), message: "Cannot strike out"}})
    end
  end

  def claim(conn, %{"code" => code, "prize" => prize, "ticket_id" => ticket_id}) do
    valid_prizes = ~w(early_five top_line middle_line bottom_line full_house)

    if prize in valid_prizes do
      prize_atom = String.to_existing_atom(prize)

      case Game.claim_prize(String.upcase(code), conn.assigns.current_user.id, ticket_id, prize_atom) do
        {:ok, prize} ->
          json(conn, %{prize: prize})

        {:error, :already_claimed} ->
          conn
          |> put_status(409)
          |> json(%{error: %{code: "already_claimed", message: "Prize already claimed"}})

        {:error, :bogey, remaining} ->
          conn
          |> put_status(422)
          |> json(%{error: %{code: "bogey", message: "Invalid claim", remaining: remaining}})

        {:error, :disqualified} ->
          conn
          |> put_status(403)
          |> json(%{error: %{code: "disqualified", message: "You are disqualified"}})

        {:error, reason} ->
          conn
          |> put_status(422)
          |> json(%{error: %{code: to_string(reason), message: "Claim failed"}})
      end
    else
      conn |> put_status(422) |> json(%{error: %{code: "invalid_prize", message: "Invalid prize"}})
    end
  end

  def set_ticket_count(conn, %{"code" => code, "user_id" => user_id, "count" => count}) do
    case Game.set_ticket_count(String.upcase(code), conn.assigns.current_user.id, user_id, count) do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, :not_host} ->
        conn |> put_status(403) |> json(%{error: %{code: "not_host", message: "Only the host can do this"}})

      {:error, :player_not_found} ->
        conn |> put_status(404) |> json(%{error: %{code: "player_not_found", message: "Player not found"}})

      {:error, :invalid_count} ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_count", message: "Count must be between 1 and 6"}})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: %{code: to_string(reason), message: "Cannot set ticket count"}})
    end
  end

  defp handle_host_action(conn, code, action) do
    case action.(String.upcase(code), conn.assigns.current_user.id) do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, :not_host} ->
        conn
        |> put_status(403)
        |> json(%{error: %{code: "not_host", message: "Only the host can do this"}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: to_string(reason), message: "Action failed"}})
    end
  end
end

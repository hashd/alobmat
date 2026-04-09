defmodule MothWeb.API.GameController do
  use MothWeb, :controller

  alias Moth.Game

  def create(conn, params) do
    user = conn.assigns.current_user

    settings = %{
      interval: params["interval"] || 30,
      bogey_limit: params["bogey_limit"] || 3,
      enabled_prizes: [:early_five, :top_line, :middle_line, :bottom_line, :full_house]
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

  def join(conn, %{"code" => code}) do
    case Game.join_game(String.upcase(code), conn.assigns.current_user.id) do
      {:ok, ticket} ->
        json(conn, %{ticket: ticket})

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

  def claim(conn, %{"code" => code, "prize" => prize}) do
    prize_atom = String.to_existing_atom(prize)

    case Game.claim_prize(String.upcase(code), conn.assigns.current_user.id, prize_atom) do
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

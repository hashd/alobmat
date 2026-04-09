defmodule MothWeb.GameChannel do
  use Phoenix.Channel

  alias Moth.Game

  def join("game:" <> code, _params, socket) do
    code = String.upcase(code)
    user_id = socket.assigns.current_user.id

    case Game.join_game(code, user_id) do
      {:ok, ticket} ->
        Phoenix.PubSub.subscribe(Moth.PubSub, "game:#{code}")

        case Game.game_state(code) do
          {:ok, state} ->
            socket = assign(socket, :code, code)
            {:ok, %{game: state, ticket: ticket}, socket}

          {:error, _} ->
            {:error, %{reason: "Game unavailable"}}
        end

      {:error, reason} ->
        {:error, %{reason: to_string(reason)}}
    end
  end

  def handle_in("strike_out", %{"number" => number}, socket) do
    case Game.strike_out(socket.assigns.code, socket.assigns.current_user.id, number) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("message", %{"text" => text}, socket) do
    Game.send_chat(socket.assigns.code, socket.assigns.current_user.id, text)
    {:noreply, socket}
  end

  def handle_info({event, payload}, socket) do
    push(socket, to_string(event), payload_to_json(payload))
    {:noreply, socket}
  end

  defp payload_to_json(payload) when is_map(payload) do
    payload
    |> Enum.map(fn {k, v} -> {to_string(k), serialize_value(v)} end)
    |> Map.new()
  end

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(v) when is_atom(v), do: to_string(v)
  defp serialize_value(v), do: v
end

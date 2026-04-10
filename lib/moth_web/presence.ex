defmodule MothWeb.Presence do
  use Phoenix.Presence,
    otp_app: :moth,
    pubsub_server: Moth.PubSub

  def track_player(socket, code, user) do
    track(socket, "game:#{code}:presence", user.id, %{
      name: user.name,
      status: :online,
      joined_at: System.monotonic_time(:millisecond)
    })
  end

  def update_status(socket, code, user_id, status) do
    update(socket, "game:#{code}:presence", user_id, fn meta ->
      Map.put(meta, :status, status)
    end)
  end

  def list_players(code) do
    list("game:#{code}:presence")
  end
end

defmodule MothWeb.Presence do
  use Phoenix.Presence,
    otp_app: :moth,
    pubsub_server: Moth.PubSub

  def track_player(socket_or_pid, code, user) do
    pid = to_pid(socket_or_pid)
    track(pid, "game:#{code}", user.id, %{
      name: user.name,
      status: :online,
      joined_at: System.monotonic_time(:millisecond)
    })
  end

  def update_status(socket_or_pid, code, user_id, status) do
    pid = to_pid(socket_or_pid)
    update(pid, "game:#{code}", user_id, fn meta ->
      Map.put(meta, :status, status)
    end)
  end

  defp to_pid(%{channel_pid: pid}), do: pid
  defp to_pid(pid) when is_pid(pid), do: pid

  def list_players(code) do
    list("game:#{code}")
  end
end

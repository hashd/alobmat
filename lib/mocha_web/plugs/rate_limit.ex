defmodule MochaWeb.Plugs.RateLimit do
  @moduledoc "ETS-based token bucket rate limiter."
  import Plug.Conn
  import Phoenix.Controller

  @table :rate_limit_buckets

  def init(opts), do: opts

  def call(conn, opts) do
    ensure_table()
    key = rate_limit_key(conn, opts)
    limit = Keyword.get(opts, :limit, 60)
    window = Keyword.get(opts, :window, 60_000)

    case check_rate(key, limit, window) do
      :ok ->
        conn

      :rate_limited ->
        conn
        |> put_status(429)
        |> json(%{error: %{code: "rate_limited", message: "Too many requests"}})
        |> halt()
    end
  end

  defp rate_limit_key(conn, opts) do
    scope = Keyword.get(opts, :scope, :ip)

    case scope do
      :ip ->
        {:ip, conn.remote_ip}

      :user ->
        {:user, conn.assigns[:current_user] && conn.assigns[:current_user].id}

      :user_ip ->
        {:user_ip, conn.assigns[:current_user] && conn.assigns[:current_user].id, conn.remote_ip}
    end
  end

  defp check_rate(key, limit, window) do
    now = System.monotonic_time(:millisecond)

    # Atomic increment-then-check to avoid TOCTOU race
    try do
      new_count = :ets.update_counter(@table, key, {2, 1})
      [{^key, ^new_count, window_start}] = :ets.lookup(@table, key)

      if now - window_start >= window do
        # Window expired — reset counter
        :ets.insert(@table, {key, 1, now})
        :ok
      else
        if new_count > limit, do: :rate_limited, else: :ok
      end
    catch
      :error, :badarg ->
        # Key doesn't exist yet — create it
        :ets.insert(@table, {key, 1, now})
        :ok
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table])
      _ -> :ok
    end
  end
end

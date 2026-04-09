defmodule Moth.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Registry for game processes
      {Registry, keys: :unique, name: Moth.Games},
      # Start the Ecto repository
      Moth.Repo,
      # Start the Telemetry supervisor
      MothWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Moth.PubSub},
      # Start Phoenix Presence for players
      MothWeb.Players,
      # Start the Endpoint (http/https)
      MothWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Moth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MothWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

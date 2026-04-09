defmodule Moth.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Moth.Repo,
      {Phoenix.PubSub, name: Moth.PubSub},
      {Finch, name: Moth.Finch},
      MothWeb.Telemetry,
      MothWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Moth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MothWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

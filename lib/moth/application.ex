defmodule Moth.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Moth.Repo,
      {DNSCluster, query: Application.get_env(:moth, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Moth.PubSub},
      {Finch, name: Moth.Finch},
      MothWeb.Telemetry,
      Moth.Game.Supervisor,
      MothWeb.Presence,
      MothWeb.Endpoint
    ]

    opts = [strategy: :rest_for_one, name: Moth.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MothWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

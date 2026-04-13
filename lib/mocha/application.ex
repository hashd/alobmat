defmodule Mocha.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Mocha.Repo,
      {DNSCluster, query: Application.get_env(:mocha, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mocha.PubSub},
      {Finch, name: Mocha.Finch},
      MochaWeb.Telemetry,
      Mocha.Game.Supervisor,
      MochaWeb.Presence,
      MochaWeb.Endpoint
    ]

    opts = [strategy: :rest_for_one, name: Mocha.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MochaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

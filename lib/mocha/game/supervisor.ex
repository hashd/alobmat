defmodule Mocha.Game.Supervisor do
  @moduledoc """
  Top-level supervisor for the game engine subsystem.
  Uses rest_for_one: if Registry or DynSup restart, Monitor restarts too.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Registry, keys: :unique, name: Mocha.Game.Registry},
      {DynamicSupervisor, name: Mocha.Game.DynSup, strategy: :one_for_one},
      Mocha.Game.Monitor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

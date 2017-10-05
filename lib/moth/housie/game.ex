defmodule Moth.Housie do
  require IEx
  alias Moth.GameServer

  def start(name, interval \\ 45) do
    case Registry.lookup(Moth.Games, name) do
      [] -> GameServer.start_link(name, interval)
      _  -> {:error, "Server is already registered with name: #{name}"}
    end
  end
end
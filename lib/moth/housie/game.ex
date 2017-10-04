defmodule Moth.Housie do
  alias Moth.GameServer

  def start(name, interval \\ 45) do
    case Registry.register(Moth.Games, name, :none) do
      {:ok, _} ->
        {:ok, gs} = GameServer.start_link(name, interval)
        Registry.unregister(Moth.Games, name)
        Registry.register(Moth.Games, name, gs)
        {:ok, gs}
      {:error, _} ->
        {:error, "Server is already registered with name: #{name}"}
    end
  end
end
defmodule Moth.GameServer do
  use GenServer
  alias Moth.{HousieBoard, GameServer}
  defstruct id: :none, time_left: 0, interval: 45, board: nil, timer: :none

  def start_link(id, interval \\ 45) do
    GenServer.start_link __MODULE__, %{id: id, interval: interval}
  end

  def init(%{id: id, interval: interval}) do
    Registry.register(Moth.Games, id, self())
    {:ok, board} = HousieBoard.start_link()
    timer = Process.send_after(self(), :update, 1_000)
    {:ok, %GameServer{id: id, timer: timer, board: board, interval: interval}}
  end

  # Client Functions
  def halt(name) do
    GenServer.call(name, :halt)
  end

  def resume(name) do
    GenServer.call(name, :resume)
  end

  def state(name) do
    GenServer.call(name, :state)
  end

  # Server Functions
  def handle_call(:state, _from, %{board: board} = state) do
    {:reply, HousieBoard.state(board), state}
  end

  def handle_call(:halt, _from, %{timer: timer} = state) do
    Process.cancel_timer(timer)
    {:reply, :ok, state}
  end

  def handle_call(:resume, _from, state) do
    timer = Process.send_after(self(), :update, 1_000)
    {:reply, :ok, Map.put(state, :timer, timer)}
  end

  def handle_info(:update, %{id: id, timer: timer, board: board, time_left: 0, interval: interval} = state) do
    pick = HousieBoard.pick(board)
    MothWeb.Endpoint.broadcast! "game:#{id}", "new_pick", %{pick: pick}

    case HousieBoard.has_finished?(board) do
      true -> 
        Process.exit(self(), :kill)
        {:noreply, state}
      _  ->
        timer = Process.send_after(self(), :update, 1_000)
        {:noreply, state |> Map.put(:timer, timer) |> Map.put(:time_left, interval - 1)}
    end
  end
  def handle_info(:update, %{id: id, time_left: time_left} = state) do
    MothWeb.Endpoint.broadcast! "game:#{id}", "time_to_pick", %{remaining: time_left}
    
    timer = Process.send_after(self(), :update, 1_000)
    {:noreply, state |> Map.put(:timer, timer) |> Map.put(:time_left, time_left - 1)}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
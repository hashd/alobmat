defmodule Moth.Housie.Server do
  use GenServer
  alias Moth.{Housie}
  alias Moth.Housie.{Board, Server}
  defstruct id: :none, time_left: 0, interval: 45, board: nil, timer: :none

  def start_link(id, name, interval \\ 45) do
    GenServer.start_link __MODULE__, %{id: id, name: name, interval: interval}
  end

  def init(%{id: id, name: name, interval: interval} = params) do
    Registry.register(Moth.Games, id, name)
    MothWeb.Endpoint.broadcast! "public:lobby", "new_game", Housie.get_game!(id)

    {:ok, board} = Board.start_link()
    timer = Process.send_after(self(), :update, 1_000)
    {:ok, %Server{id: id, timer: timer, board: board, interval: interval}}
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
    {:reply, Board.state(board), state}
  end

  def handle_call(:halt, _from, %{timer: timer} = state) do
    Process.cancel_timer(timer)
    {:reply, :ok, state}
  end

  def handle_call(:resume, _from, state) do
    timer = Process.send_after(self(), :update, 1_000)
    {:reply, :ok, Map.put(state, :timer, timer)}
  end

  def handle_info(:end, state) do
    # TODO: Persist data and end server
    # Process.exit(self(), :kill)
    game = Housie.get_game!(state.id)
    Housie.update_game(game, %{status: "ended", moderators: game.moderators |> Enum.map(fn m -> m.id end)})

    IO.inspect "Hopefully game was updated"
    MothWeb.Endpoint.broadcast! "public:lobby", "end_game", %{id: state.id}
    {:noreply, state}
  end

  def handle_info(:update, %{id: id, timer: timer, board: board, time_left: 0, interval: interval} = state) do
    pick = Board.pick(board)
    MothWeb.Endpoint.broadcast! "game:#{id}", "pick", %{pick: pick}

    case Board.has_finished?(board) do
      true -> 
        Process.send(self(), :end, [:noconnect])
        {:noreply, state}
      _  ->
        timer = Process.send_after(self(), :update, 1_000)
        {:noreply, state |> Map.put(:timer, timer) |> Map.put(:time_left, interval - 1)}
    end
  end
  def handle_info(:update, %{id: id, time_left: time_left} = state) do
    MothWeb.Endpoint.broadcast! "game:#{id}", "timer", %{remaining: time_left}
    
    timer = Process.send_after(self(), :update, 1_000)
    {:noreply, state |> Map.put(:timer, timer) |> Map.put(:time_left, time_left - 1)}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
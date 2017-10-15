defmodule Moth.Housie.Server do
  use GenServer
  alias Moth.{Housie}
  alias Moth.Housie.{Board, Server}
  defstruct id: :none, time_left: 0, interval: 45, board: nil, timer: :none, status: :running

  def start_link(id, name, interval \\ 45) do
    GenServer.start_link __MODULE__, %{id: id, name: name, interval: interval}
  end

  def init(%{id: id, name: name, interval: interval} = _params) do
    Registry.register(Moth.Games, id, name)
    MothWeb.Endpoint.broadcast! "public:lobby", "new_game", Housie.get_game!(id)

    {:ok, board} = Board.start_link()
    timer = Process.send_after(self(), :update, 1_000)
    {:ok, %Server{id: id, timer: timer, board: board, interval: interval, time_left: interval - 1}}
  end

  # Client Functions
  def pause(name) do
    GenServer.call(name, :pause)
  end

  def resume(name) do
    GenServer.call(name, :resume)
  end

  def state(name) do
    GenServer.call(name, :state)
  end

  # Server Functions
  def handle_call(:state, _from, state) do
    {:reply, server_state(state), state}
  end

  def handle_call(:pause, _from, %{timer: timer} = state) do
    Process.cancel_timer(timer)
    state = Map.put(state, :status, :paused)
    {:reply, server_state(state), state}
  end

  def handle_call(:resume, _from, state) do
    timer = Process.send_after(self(), :update, 1_000)
    state = state |> Map.put(:status, :running) |> Map.put(:timer, timer)
    {:reply, server_state(state), state}
  end

  def handle_info(:end, state) do
    {:stop, :shutdown, state |> Map.put(:status, :finished)}
  end

  def handle_info(:update, %{id: id, timer: timer, board: board, time_left: 0, interval: interval} = state) do
    # Timer is 0, pick a number, broadcast and then choose the next action plan
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
    # Timer is !0, so reduce timer by 1 and broadcast timer to everyone on channel
    MothWeb.Endpoint.broadcast! "game:#{id}", "timer", %{remaining: time_left}
    
    timer = Process.send_after(self(), :update, 1_000)
    {:noreply, state |> Map.put(:timer, timer) |> Map.put(:time_left, time_left - 1)}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  def terminate(:shutdown, state) do
    # Update game status to ended
    game = Housie.get_game!(state.id)
    Housie.update_game(game, %{
      status: "ended",
      finished_at: DateTime.utc_now,
      moderators: game.moderators |> Enum.map(fn m -> m.id end)
    })

    # Notify public lobby that this game has ended
    MothWeb.Endpoint.broadcast! "public:lobby", "end_game", %{id: state.id}
    :normal
  end

  defp server_state(%{board: board} = state) do
    state
    |> Map.put(:board, Board.state(board))
    |> Map.delete(:timer)
  end
end
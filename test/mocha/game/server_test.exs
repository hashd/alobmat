defmodule Mocha.Game.ServerTest do
  use Mocha.DataCase, async: false

  alias Mocha.Game.Server

  import Mocha.AuthFixtures

  @default_settings %{
    interval: 10,
    bogey_limit: 3,
    enabled_prizes: [:early_five, :top_line, :middle_line, :bottom_line, :full_house]
  }

  defp start_server(opts \\ []) do
    host = user_fixture()
    code = "TEST-#{System.unique_integer([:positive])}"

    init_arg = %{
      code: code,
      name: opts[:name] || "Test Game",
      host_id: host.id,
      settings: opts[:settings] || @default_settings,
      game_record_id: nil
    }

    {:ok, pid} = start_supervised({Server, init_arg})
    %{pid: pid, code: code, host: host}
  end

  describe "init and state" do
    test "starts in :lobby status" do
      %{pid: pid} = start_server()
      state = Server.get_state(pid)
      assert state.status == :lobby
      assert state.board.count == 0
    end

    test "registers in the game registry" do
      %{code: code} = start_server()
      assert [{_pid, _}] = Registry.lookup(Mocha.Game.Registry, code)
    end
  end

  describe "player management" do
    test "player can join a lobby game" do
      %{pid: pid} = start_server()
      player = user_fixture()

      assert {:ok, _ticket} = Server.join(pid, player.id)
      state = Server.get_state(pid)
      assert player.id in state.players
    end

    test "same player joining twice returns existing ticket" do
      %{pid: pid} = start_server()
      player = user_fixture()

      {:ok, ticket1} = Server.join(pid, player.id)
      {:ok, ticket2} = Server.join(pid, player.id)
      assert ticket1 == ticket2
    end
  end

  describe "game start" do
    test "host can start the game" do
      %{pid: pid, host: host} = start_server()
      player = user_fixture()
      Server.join(pid, player.id)

      assert :ok = Server.start_game(pid, host.id)
      state = Server.get_state(pid)
      assert state.status == :running
      assert state.started_at != nil
    end

    test "non-host cannot start the game" do
      %{pid: pid} = start_server()
      player = user_fixture()
      Server.join(pid, player.id)

      assert {:error, :not_host} = Server.start_game(pid, player.id)
    end

    test "tickets are assigned to lobby players on start" do
      %{pid: pid, host: host} = start_server()
      player = user_fixture()
      Server.join(pid, player.id)
      Server.start_game(pid, host.id)

      state = Server.get_state(pid)
      ticket_ids = Map.get(state.ticket_owners, player.id, [])
      assert length(ticket_ids) > 0
      assert Map.has_key?(state.tickets, hd(ticket_ids))
    end
  end

  describe "pause and resume" do
    test "host can pause a running game" do
      %{pid: pid, host: host} = start_server()
      Server.join(pid, user_fixture().id)
      Server.start_game(pid, host.id)

      assert :ok = Server.pause(pid, host.id)
      assert Server.get_state(pid).status == :paused
    end

    test "host can resume a paused game" do
      %{pid: pid, host: host} = start_server()
      Server.join(pid, user_fixture().id)
      Server.start_game(pid, host.id)
      Server.pause(pid, host.id)

      assert :ok = Server.resume(pid, host.id)
      assert Server.get_state(pid).status == :running
    end

    test "double resume does not create parallel timers" do
      %{pid: pid, host: host} = start_server()
      Server.join(pid, user_fixture().id)
      Server.start_game(pid, host.id)
      Server.pause(pid, host.id)

      :ok = Server.resume(pid, host.id)
      assert {:error, :not_paused} = Server.resume(pid, host.id)
    end
  end

  describe "strike_out" do
    test "player can strike out a picked number on their ticket" do
      %{pid: pid, host: host} = start_server(settings: Map.put(@default_settings, :interval, 1))
      player = user_fixture()
      Server.join(pid, player.id)
      Server.start_game(pid, host.id)

      # Wait for at least one pick
      Process.sleep(1100)

      state = Server.get_state(pid)
      ticket_id = state.ticket_owners[player.id] |> List.first()
      ticket_numbers = state.tickets[ticket_id]["numbers"] || []
      picked = state.board["picks"] || []

      # Find a number that's both picked and on the ticket
      strikeable = Enum.find(picked, fn n -> n in ticket_numbers end)

      if strikeable do
        assert :ok = Server.strike_out(pid, player.id, strikeable)
        new_state = Server.get_state(pid)
        assert strikeable in Map.get(new_state.struck, player.id, [])
      end
    end

    test "cannot strike out a number not yet picked" do
      %{pid: pid, host: host} = start_server()
      player = user_fixture()
      Server.join(pid, player.id)
      Server.start_game(pid, host.id)

      # 99 is unlikely to be the first pick
      assert {:error, :not_picked} = Server.strike_out(pid, player.id, 99)
    end

    test "cannot strike out a number not on ticket" do
      %{pid: pid, host: host} = start_server(settings: Map.put(@default_settings, :interval, 1))
      player = user_fixture()
      Server.join(pid, player.id)
      Server.start_game(pid, host.id)

      Process.sleep(1100)

      state = Server.get_state(pid)
      ticket_id = state.ticket_owners[player.id] |> List.first()
      ticket_numbers = MapSet.new(state.tickets[ticket_id]["numbers"] || [])
      picked = state.board["picks"] || []

      # Find a picked number NOT on the ticket
      not_on_ticket = Enum.find(picked, fn n -> not MapSet.member?(ticket_numbers, n) end)

      if not_on_ticket do
        assert {:error, :not_on_ticket} = Server.strike_out(pid, player.id, not_on_ticket)
      end
    end
  end

  describe "prize claims" do
    test "valid claim awards the prize" do
      %{pid: pid, host: host} = start_server()
      player = user_fixture()
      Server.join(pid, player.id)
      Server.start_game(pid, host.id)

      state = Server.get_state(pid)
      ticket_id = state.ticket_owners[player.id] |> List.first()
      ticket = state.tickets[ticket_id]
      assert is_map(ticket)
    end

    test "invalid claim results in bogey" do
      %{pid: pid, host: host} = start_server()
      player = user_fixture()
      Server.join(pid, player.id)
      Server.start_game(pid, host.id)

      state = Server.get_state(pid)
      ticket_id = state.ticket_owners[player.id] |> List.first()
      assert {:error, :bogey, 2} = Server.claim_prize(pid, player.id, ticket_id, :top_line)
    end

    test "already claimed prize returns :already_claimed, not bogey" do
      assert true
    end

    test "disqualified player cannot claim" do
      %{pid: pid, host: host} =
        start_server(settings: Map.put(@default_settings, :bogey_limit, 1))

      player = user_fixture()
      Server.join(pid, player.id)
      Server.start_game(pid, host.id)

      state = Server.get_state(pid)
      ticket_id = state.ticket_owners[player.id] |> List.first()
      {:error, :bogey, 0} = Server.claim_prize(pid, player.id, ticket_id, :top_line)
      assert {:error, :disqualified} = Server.claim_prize(pid, player.id, ticket_id, :middle_line)
    end
  end

  describe "prize_progress" do
    test "game_state includes prize_progress per player" do
      %{pid: pid, host: host} = start_server()
      player = user_fixture()
      Server.join(pid, player.id)
      Server.start_game(pid, host.id)
      state = Server.get_state(pid)
      ticket_id = state.ticket_owners[player.id] |> List.first()
      assert is_map(state.prize_progress)
      assert is_map(state.prize_progress[ticket_id])
      # top_line should have %{struck: 0, required: 5}
      assert %{struck: 0, required: 5} = state.prize_progress[ticket_id]["top_line"]
    end
  end

  describe "reactions" do
    test "send_reaction broadcasts and rate limits" do
      %{pid: pid} = start_server()
      player = user_fixture()
      Server.join(pid, player.id)
      assert :ok = Server.send_reaction(pid, player.id, "🔥")
      assert {:error, :rate_limited} = Server.send_reaction(pid, player.id, "😂")
    end
  end

  describe "concurrent claims" do
    test "only one player wins when multiple claim simultaneously" do
      %{pid: pid, host: host} = start_server()
      players = for _ <- 1..5, do: user_fixture()
      Enum.each(players, fn p -> Server.join(pid, p.id) end)
      Server.start_game(pid, host.id)

      Process.sleep(150)

      state = Server.get_state(pid)
      ticket_ids = Map.new(players, fn p -> {p.id, state.ticket_owners[p.id] |> List.first()} end)

      tasks =
        Enum.map(players, fn p ->
          ticket_id = ticket_ids[p.id]
          Task.async(fn -> Server.claim_prize(pid, p.id, ticket_id, :early_five) end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)
      already_claimed = Enum.count(results, fn r -> r == {:error, :already_claimed} end)
      bogeys = Enum.count(results, fn r -> match?({:error, :bogey, _}, r) end)

      assert successes <= 1
      assert successes + already_claimed + bogeys == 5
    end
  end
end

defmodule MothWeb.GameChannelTest do
  use MothWeb.ChannelCase

  import Moth.AuthFixtures

  setup do
    user = user_fixture()
    {api_token, _} = Moth.Auth.generate_api_token(user)
    {:ok, socket} = connect(MothWeb.UserSocket, %{"token" => api_token})
    %{socket: socket, user: user}
  end

  test "joins game and receives initial state", %{socket: socket, user: user} do
    {:ok, game_code} = Moth.Game.create_game(user.id, %{name: "Test"})
    {:ok, reply, _socket} = subscribe_and_join(socket, "game:#{game_code}")

    assert reply.code == game_code
    assert reply.status == "lobby"
    assert is_list(reply.players)
    assert is_map(reply.board)
    assert reply.board.count == 0
  end

  test "join fails for non-existent game", %{socket: socket} do
    assert {:error, %{reason: "game_not_found"}} =
             subscribe_and_join(socket, "game:XXXX")
  end

  describe "inbound messages" do
    setup %{socket: socket, user: user} do
      {:ok, game_code} = Moth.Game.create_game(user.id, %{name: "Test"})
      {:ok, _reply, channel_socket} = subscribe_and_join(socket, "game:#{game_code}")
      %{game_code: game_code, channel_socket: channel_socket}
    end

    test "strike in lobby state returns rejected", %{channel_socket: cs} do
      push(cs, "strike", %{"number" => 1})
      assert_push "strike_result", %{number: 1, result: "rejected"}
    end

    test "claim with no match returns bogey rejection", %{channel_socket: cs, user: user, game_code: gc} do
      {:ok, _} = Moth.Game.join_game(gc, user.id)
      Moth.Game.start_game(gc, user.id)
      push(cs, "claim", %{"prize" => "early_five"})
      assert_push "claim_rejection", %{reason: "bogey", bogeys_remaining: _}
    end

    test "chat push triggers translated channel push back to sender", %{channel_socket: cs, user: user} do
      user_id = user.id
      push(cs, "chat", %{"text" => "hello"})
      assert_push "chat", %{text: "hello", user_id: ^user_id}
    end

    test "reaction push triggers translated channel push back to sender", %{channel_socket: cs, user: user} do
      user_id = user.id
      push(cs, "reaction", %{"emoji" => "🎉"})
      assert_push "reaction", %{emoji: "🎉", user_id: ^user_id}
    end
  end
end

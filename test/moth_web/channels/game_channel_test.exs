defmodule MothWeb.GameChannelTest do
  use MothWeb.ChannelCase

  import Moth.AuthFixtures
  import Moth.GameFixtures

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
end

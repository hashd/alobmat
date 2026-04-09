defmodule MothWeb.API.GameControllerTest do
  use MothWeb.ConnCase, async: false

  import Moth.AuthFixtures

  setup %{conn: conn} do
    user = user_fixture()
    {token, _} = Moth.Auth.generate_api_token(user)
    conn = put_req_header(conn, "authorization", "Bearer #{token}")
    %{conn: conn, user: user}
  end

  describe "POST /api/games" do
    test "creates a game", %{conn: conn} do
      conn = post(conn, ~p"/api/games", %{name: "Test Game", interval: 30})
      assert %{"code" => code} = json_response(conn, 201)
      assert is_binary(code)
    end
  end

  describe "GET /api/games/:code" do
    test "returns game state", %{conn: conn, user: user} do
      {:ok, code} = Moth.Game.create_game(user.id, %{name: "Test"})
      conn = get(conn, ~p"/api/games/#{code}")
      assert %{"game" => _game} = json_response(conn, 200)
    end

    test "returns 404 for unknown code", %{conn: conn} do
      conn = get(conn, ~p"/api/games/NOPE-00")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/games/:code/join" do
    test "joins the game", %{conn: conn, user: user} do
      {:ok, code} = Moth.Game.create_game(user.id, %{name: "Test"})
      other = user_fixture()
      {other_token, _} = Moth.Auth.generate_api_token(other)
      conn = put_req_header(build_conn(), "authorization", "Bearer #{other_token}")
      conn = post(conn, ~p"/api/games/#{code}/join")
      assert json_response(conn, 200)
    end
  end
end

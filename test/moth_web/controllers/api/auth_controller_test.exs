defmodule MothWeb.API.AuthControllerTest do
  use MothWeb.ConnCase, async: false

  import Moth.AuthFixtures

  describe "POST /api/auth/magic" do
    test "sends magic link", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/magic", %{email: "test@example.com"})
      assert %{"status" => "ok"} = json_response(conn, 200)
    end
  end

  describe "POST /api/auth/verify" do
    test "verifies magic link and returns token", %{conn: conn} do
      user = user_fixture()
      {token, _} = Moth.Auth.build_magic_link_token(user.email)

      conn = post(conn, ~p"/api/auth/verify", %{token: token})
      assert %{"token" => api_token, "user" => _} = json_response(conn, 200)
      assert is_binary(api_token)
    end

    test "rejects invalid token", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/verify", %{token: "invalid"})
      assert json_response(conn, 401)
    end
  end
end

defmodule MothWeb.API.AuthControllerTest do
  use MothWeb.ConnCase, async: false

  import Moth.AuthFixtures
  import Ecto.Query

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

  describe "POST /api/auth/otp/request" do
    test "returns ok for valid phone", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/otp/request", %{phone: "9876543210"})
      assert %{"status" => "ok"} = json_response(conn, 200)
    end

    test "returns 422 for invalid phone", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/otp/request", %{phone: "123"})
      assert %{"error" => %{"code" => "invalid_phone"}} = json_response(conn, 422)
    end

    test "returns 429 when rate limited", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})

      conn = post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert %{"error" => %{"code" => "rate_limited"}} = json_response(conn, 429)
    end
  end

  describe "POST /api/auth/otp/verify" do
    test "correct code for new user returns token and needs_name: true", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, code}

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: code})
      resp = json_response(conn, 200)
      assert resp["token"]
      assert resp["needs_name"] == true
      assert resp["user"]["phone"] == phone
    end

    test "correct code for existing user returns needs_name: false", %{conn: conn} do
      user = phone_user_fixture(%{phone: "+919876543210"})

      post(conn, ~p"/api/auth/otp/request", %{phone: user.phone})
      assert_received {:otp_sent, _, code}

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: user.phone, code: code})
      resp = json_response(conn, 200)
      assert resp["needs_name"] == false
      assert resp["user"]["id"] == user.id
    end

    test "wrong code returns 401 with attempts_remaining", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, _code}

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})
      resp = json_response(conn, 401)
      assert resp["error"]["code"] == "invalid_otp"
      assert resp["error"]["attempts_remaining"] == 2
    end

    test "exhausted attempts returns 429", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, _code}

      post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})
      post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})
      post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: "000000"})
      assert %{"error" => %{"code" => "too_many_attempts"}} = json_response(conn, 429)
    end

    test "expired OTP returns 401", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, code}

      # Expire the OTP
      Moth.Repo.update_all(
        from(o in Moth.Auth.PhoneOtpCode, where: o.phone == ^phone),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
      )

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: code})
      assert %{"error" => %{"code" => "invalid_otp"}} = json_response(conn, 401)
    end

    test "token from OTP verify works for authenticated endpoints", %{conn: conn} do
      phone = "+919876543210"
      post(conn, ~p"/api/auth/otp/request", %{phone: phone})
      assert_received {:otp_sent, ^phone, code}

      conn = post(conn, ~p"/api/auth/otp/verify", %{phone: phone, code: code})
      %{"token" => token} = json_response(conn, 200)

      # Use the token to access an authenticated endpoint
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/user/me")

      assert %{"user" => %{"phone" => ^phone}} = json_response(conn, 200)
    end
  end
end

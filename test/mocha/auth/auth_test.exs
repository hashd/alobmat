defmodule Mocha.AuthTest do
  use Mocha.DataCase, async: false

  alias Mocha.Auth
  alias Mocha.Auth.{User, UserToken, PhoneOtpCode}

  import Mocha.AuthFixtures

  describe "register/1" do
    test "creates a user with valid attrs" do
      attrs = valid_user_attributes()
      assert {:ok, %User{} = user} = Auth.register(attrs)
      assert user.email == attrs.email
      assert user.name == attrs.name
    end

    test "rejects duplicate emails" do
      attrs = valid_user_attributes()
      {:ok, _} = Auth.register(attrs)
      assert {:error, changeset} = Auth.register(attrs)
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "get_user!/1" do
    test "returns the user with the given id" do
      user = user_fixture()
      assert Auth.get_user!(user.id).id == user.id
    end
  end

  describe "session tokens" do
    test "generate and verify session token" do
      user = user_fixture()
      token = Auth.generate_user_session_token(user)
      assert is_binary(token)

      found_user = Auth.get_user_by_session_token(token)
      assert found_user.id == user.id
    end

    test "expired session token returns nil" do
      user = user_fixture()
      token = Auth.generate_user_session_token(user)

      Mocha.Repo.update_all(
        from(t in UserToken, where: t.user_id == ^user.id and t.context == "session"),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
      )

      assert Auth.get_user_by_session_token(token) == nil
    end
  end

  describe "API tokens" do
    test "generate and verify API token" do
      user = user_fixture()
      {token, _token_record} = Auth.generate_api_token(user)
      assert is_binary(token)

      assert {:ok, found_user} = Auth.get_user_by_api_token(token)
      assert found_user.id == user.id
    end
  end

  describe "magic link tokens" do
    test "build and verify magic link" do
      user = user_fixture()
      {:ok, token, _token_record} = Auth.build_magic_link_token(user.email)
      assert is_binary(token)

      assert {:ok, found_user} = Auth.verify_magic_link(token)
      assert found_user.id == user.id
    end

    test "magic link is single-use" do
      user = user_fixture()
      {:ok, token, _} = Auth.build_magic_link_token(user.email)

      assert {:ok, _} = Auth.verify_magic_link(token)
      assert Auth.verify_magic_link(token) == :error
    end
  end

  describe "revoke_all_tokens/1" do
    test "revokes all tokens for a user" do
      user = user_fixture()
      session_token = Auth.generate_user_session_token(user)
      {api_token, _} = Auth.generate_api_token(user)

      Auth.revoke_all_tokens(user)

      assert Auth.get_user_by_session_token(session_token) == nil
      assert Auth.get_user_by_api_token(api_token) == :error
    end
  end

  describe "request_phone_otp/1" do
    test "creates OTP record and returns :ok" do
      assert :ok = Auth.request_phone_otp("+919876543210")
      assert_received {:otp_sent, "+919876543210", code}
      assert String.length(code) == 6
      assert String.match?(code, ~r/^\d{6}$/)
    end

    test "invalidates previous unexpired OTPs on resend" do
      assert :ok = Auth.request_phone_otp("+919876543210")
      assert :ok = Auth.request_phone_otp("+919876543210")

      # Only one active (unused) OTP should exist
      active =
        Repo.all(
          from o in PhoneOtpCode,
            where: o.phone == "+919876543210" and is_nil(o.used_at)
        )

      assert length(active) == 1
    end

    test "rate-limits at 3 requests per 10 minutes" do
      phone = "+919876543210"
      assert :ok = Auth.request_phone_otp(phone)
      assert :ok = Auth.request_phone_otp(phone)
      assert :ok = Auth.request_phone_otp(phone)
      assert {:error, :rate_limited} = Auth.request_phone_otp(phone)
    end

    test "returns :ok even for unknown phones (anti-enumeration)" do
      assert :ok = Auth.request_phone_otp("+919999999999")
    end
  end

  describe "verify_phone_otp/2" do
    test "correct code for new phone creates user and returns needs_name: true" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      assert {:ok, %{user: user, token: token, needs_name: true}} =
               Auth.verify_phone_otp(phone, code)

      assert user.phone == phone
      assert user.name == phone
      assert is_binary(token)
    end

    test "correct code for existing phone user returns needs_name: false" do
      phone = "+919876543210"

      {:ok, existing} =
        %User{}
        |> User.phone_registration_changeset(%{phone: phone, name: "Priya"})
        |> Repo.insert()

      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      assert {:ok, %{user: user, token: _token, needs_name: false}} =
               Auth.verify_phone_otp(phone, code)

      assert user.id == existing.id
    end

    test "wrong code returns error with attempts_remaining" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, _code}

      assert {:error, :invalid_otp, 2} = Auth.verify_phone_otp(phone, "000000")
      assert {:error, :invalid_otp, 1} = Auth.verify_phone_otp(phone, "000000")
      assert {:error, :invalid_otp, 0} = Auth.verify_phone_otp(phone, "000000")
    end

    test "exhausted attempts returns too_many_attempts" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      # Exhaust 3 attempts
      Auth.verify_phone_otp(phone, "000000")
      Auth.verify_phone_otp(phone, "000000")
      Auth.verify_phone_otp(phone, "000000")

      # 4th attempt with correct code still fails
      assert {:error, :too_many_attempts} = Auth.verify_phone_otp(phone, code)
    end

    test "expired OTP returns invalid_otp" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      # Manually expire the OTP
      Repo.update_all(
        from(o in PhoneOtpCode, where: o.phone == ^phone),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1)]
      )

      assert {:error, :invalid_otp} = Auth.verify_phone_otp(phone, code)
    end

    test "already-used OTP returns invalid_otp" do
      phone = "+919876543210"
      :ok = Auth.request_phone_otp(phone)
      assert_received {:otp_sent, ^phone, code}

      assert {:ok, _} = Auth.verify_phone_otp(phone, code)
      assert {:error, :invalid_otp} = Auth.verify_phone_otp(phone, code)
    end
  end
end

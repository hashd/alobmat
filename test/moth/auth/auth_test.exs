defmodule Moth.AuthTest do
  use Moth.DataCase, async: true

  alias Moth.Auth
  alias Moth.Auth.{User, UserToken}

  import Moth.AuthFixtures

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

      Moth.Repo.update_all(
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
      {token, _token_record} = Auth.build_magic_link_token(user.email)
      assert is_binary(token)

      assert {:ok, found_user} = Auth.verify_magic_link(token)
      assert found_user.id == user.id
    end

    test "magic link is single-use" do
      user = user_fixture()
      {token, _} = Auth.build_magic_link_token(user.email)

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
end

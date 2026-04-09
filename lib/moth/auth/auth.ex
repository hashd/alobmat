defmodule Moth.Auth do
  @moduledoc "The Auth context. Manages users, tokens, and authentication."

  import Ecto.Query
  alias Moth.Repo
  alias Moth.Auth.{User, UserIdentity, UserToken}

  ## User management

  def register(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  ## Session tokens (raw binary, stored in cookie)

  def generate_user_session_token(user) do
    {token, token_record} = UserToken.build_session_token(user)
    Repo.insert!(token_record)
    token
  end

  def get_user_by_session_token(token) when is_binary(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_session_token(token) when is_binary(token) do
    hashed = :crypto.hash(:sha256, token)

    Repo.delete_all(
      from t in UserToken,
        where: t.token == ^hashed and t.context == "session"
    )

    :ok
  end

  ## API tokens (base64-encoded, sent in Authorization header)

  def generate_api_token(user) do
    {token, token_record} = UserToken.build_api_token(user)
    Repo.insert!(token_record)
    {token, token_record}
  end

  def get_user_by_api_token(token) when is_binary(token) do
    case UserToken.verify_token_query(token, "api") do
      {:ok, query} ->
        case Repo.one(query) do
          {user, _token_record} -> {:ok, user}
          nil -> :error
        end

      :error ->
        :error
    end
  end

  ## Magic link tokens

  def build_magic_link_token(email) when is_binary(email) do
    {token, token_record} =
      case get_user_by_email(email) do
        %User{} = user ->
          {t, rec} = UserToken.build_magic_link_token(email)
          {t, %{rec | user_id: user.id}}

        nil ->
          {:ok, user} = register(%{email: email, name: email_to_name(email)})
          {t, rec} = UserToken.build_magic_link_token(email)
          {t, %{rec | user_id: user.id}}
      end

    Repo.insert!(token_record)
    {token, token_record}
  end

  def verify_magic_link(token) when is_binary(token) do
    case UserToken.verify_token_query(token, "magic_link") do
      {:ok, query} ->
        case Repo.one(query) do
          {user, token_record} ->
            token_record
            |> Ecto.Changeset.change(used_at: DateTime.truncate(DateTime.utc_now(), :second))
            |> Repo.update!()

            {:ok, user}

          nil ->
            :error
        end

      :error ->
        :error
    end
  end

  ## OAuth identity linking

  def authenticate_oauth(provider, %{email: email, name: name, avatar_url: avatar_url, uid: uid}) do
    case get_user_by_email(email) do
      %User{} = user ->
        ensure_identity(user, provider, uid)
        update_user(user, %{name: name, avatar_url: avatar_url})

      nil ->
        {:ok, user} = register(%{email: email, name: name, avatar_url: avatar_url})
        ensure_identity(user, provider, uid)
        {:ok, user}
    end
  end

  defp ensure_identity(user, provider, uid) do
    case Repo.get_by(UserIdentity, user_id: user.id, provider: to_string(provider)) do
      nil ->
        %UserIdentity{}
        |> UserIdentity.changeset(%{user_id: user.id, provider: to_string(provider), provider_uid: to_string(uid)})
        |> Repo.insert()

      identity ->
        {:ok, identity}
    end
  end

  ## Token management

  def revoke_all_tokens(%User{} = user) do
    Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id)
    :ok
  end

  ## Helpers

  defp email_to_name(email) do
    email |> String.split("@") |> List.first() |> String.replace(~r/[._]/, " ") |> String.capitalize()
  end
end

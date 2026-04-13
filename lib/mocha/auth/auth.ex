defmodule Mocha.Auth do
  @moduledoc "The Auth context. Manages users, tokens, and authentication."

  import Ecto.Query
  alias Mocha.Repo
  alias Mocha.Auth.{User, UserIdentity, UserToken}
  alias Mocha.Auth.{Phone, PhoneOtpCode}

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
    case get_user_by_email(email) do
      %User{} = user ->
        {t, rec} = UserToken.build_magic_link_token(email)
        token_record = %{rec | user_id: user.id}
        Repo.insert!(token_record)
        {:ok, t, token_record}

      nil ->
        # Don't auto-register unknown emails — prevents account creation spam
        {:error, :user_not_found}
    end
  end

  def verify_magic_link(token) when is_binary(token) do
    case UserToken.verify_token_query(token, "magic_link") do
      {:ok, query} ->
        case Repo.one(query) do
          {user, token_record} ->
            # Atomic delete prevents replay — concurrent requests can't both succeed
            {deleted, _} = Repo.delete_all(
              from(t in UserToken, where: t.id == ^token_record.id and is_nil(t.used_at))
            )

            if deleted == 1, do: {:ok, user}, else: :error

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
        |> UserIdentity.changeset(%{
          user_id: user.id,
          provider: to_string(provider),
          provider_uid: to_string(uid)
        })
        |> Repo.insert()

      identity ->
        {:ok, identity}
    end
  end

  ## Token management

  def delete_api_token(raw_token) when is_binary(raw_token) do
    case UserToken.verify_token_query(raw_token, "api") do
      {:ok, query} ->
        case Repo.one(query) do
          {_user, token_record} -> Repo.delete(token_record)
          nil -> :ok
        end

      :error ->
        :ok
    end

    :ok
  end

  def revoke_all_tokens(%User{} = user) do
    Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id)
    :ok
  end

  ## Bulk lookups

  def get_users_map(ids) when is_list(ids) do
    Repo.all(from u in User, where: u.id in ^ids, select: {u.id, u.name})
    |> Map.new()
  end

  ## Phone OTP

  @otp_expiry_seconds 600
  @otp_rate_limit 3

  def request_phone_otp(phone) do
    with {:ok, normalized} <- Phone.normalize(phone) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Invalidate old unexpired OTPs for this phone
      from(o in PhoneOtpCode,
        where: o.phone == ^normalized and is_nil(o.used_at) and o.expires_at > ^now
      )
      |> Repo.update_all(set: [used_at: now])

      # Rate-limit: count OTPs inserted in last 10 minutes
      ten_min_ago = DateTime.add(now, -@otp_expiry_seconds)

      count =
        Repo.one(
          from o in PhoneOtpCode,
            where: o.phone == ^normalized and o.inserted_at > ^ten_min_ago,
            select: count(o.id)
        )

      if count >= @otp_rate_limit do
        {:error, :rate_limited}
      else
        code = generate_otp_code()
        hashed = :crypto.hash(:sha256, code)
        expires_at = DateTime.add(now, @otp_expiry_seconds)

        %PhoneOtpCode{}
        |> PhoneOtpCode.changeset(%{
          phone: normalized,
          hashed_code: hashed,
          expires_at: expires_at
        })
        |> Repo.insert!()

        case Mocha.Auth.SMSProvider.deliver_otp(normalized, code) do
          :ok ->
            :ok

          {:error, _reason} ->
            # Delete the OTP row so it doesn't count against rate limit
            Repo.delete_all(
              from(o in PhoneOtpCode,
                where: o.phone == ^normalized and o.hashed_code == ^hashed and is_nil(o.used_at)
              )
            )

            {:error, :sms_delivery_failed}
        end
      end
    end
  end

  defp generate_otp_code do
    :crypto.strong_rand_bytes(4)
    |> :binary.decode_unsigned()
    |> rem(900_000)
    |> Kernel.+(100_000)
    |> Integer.to_string()
  end

  def verify_phone_otp(phone, code) do
    with {:ok, normalized} <- Phone.normalize(phone) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      result =
        Repo.transaction(fn ->
          # Global attempt count across all OTP rows in the last 10 minutes
          ten_min_ago = DateTime.add(now, -@otp_expiry_seconds)

          total_attempts =
            Repo.one(
              from(o in PhoneOtpCode,
                where: o.phone == ^normalized and o.inserted_at > ^ten_min_ago,
                select: coalesce(sum(o.attempt_count), 0)
              )
            )

          if total_attempts >= 5 do
            {:error, :too_many_attempts}
          else
            # Lock the most recent active OTP row
            otp_record =
              Repo.one(
                from(o in PhoneOtpCode,
                  where: o.phone == ^normalized and o.expires_at > ^now and is_nil(o.used_at),
                  order_by: [desc: o.inserted_at],
                  limit: 1,
                  lock: "FOR UPDATE"
                )
              )

            case otp_record do
              nil ->
                {:error, :invalid_otp}

              %{attempt_count: attempts} when attempts >= 3 ->
                {:error, :too_many_attempts}

              record ->
                hashed_input = :crypto.hash(:sha256, code)

                if Plug.Crypto.secure_compare(hashed_input, record.hashed_code) do
                  record
                  |> Ecto.Changeset.change(used_at: now)
                  |> Repo.update!()

                  {user, needs_name} = find_or_create_phone_user(normalized)
                  {token, _} = generate_api_token(user)
                  {:ok, %{user: user, token: token, needs_name: needs_name}}
                else
                  new_count = record.attempt_count + 1

                  record
                  |> Ecto.Changeset.change(attempt_count: new_count)
                  |> Repo.update!()

                  {:error, :invalid_otp, 3 - new_count}
                end
            end
          end
        end)

      case result do
        {:ok, {:ok, data}} -> {:ok, data}
        {:ok, {:error, :invalid_otp}} -> {:error, :invalid_otp}
        {:ok, {:error, :invalid_otp, remaining}} -> {:error, :invalid_otp, remaining}
        {:ok, {:error, :too_many_attempts}} -> {:error, :too_many_attempts}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp find_or_create_phone_user(phone) do
    case Repo.get_by(User, phone: phone) do
      %User{} = user ->
        {user, false}

      nil ->
        case %User{}
             |> User.phone_registration_changeset(%{phone: phone, name: phone})
             |> Repo.insert() do
          {:ok, user} ->
            {user, true}

          {:error, %Ecto.Changeset{errors: errors}} ->
            # Handle concurrent insert race — another request created this user first
            if Keyword.has_key?(errors, :phone) do
              {Repo.get_by!(User, phone: phone), false}
            else
              raise "Unexpected error creating phone user: #{inspect(errors)}"
            end
        end
    end
  end
end

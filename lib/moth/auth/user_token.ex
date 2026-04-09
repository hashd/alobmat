defmodule Moth.Auth.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32

  # Token validity periods
  @session_validity_days 60
  @api_validity_days 30
  @magic_link_validity_minutes 15

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :user, Moth.Auth.User

    timestamps(updated_at: false)
  end

  @doc "Builds a session token for a user."
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    expires_at = DateTime.utc_now() |> DateTime.add(@session_validity_days * 86400)

    {token,
     %__MODULE__{
       token: hash_token(token),
       context: "session",
       user_id: user.id,
       expires_at: DateTime.truncate(expires_at, :second)
     }}
  end

  @doc "Builds an API token for a user."
  def build_api_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    expires_at = DateTime.utc_now() |> DateTime.add(@api_validity_days * 86400)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: hash_token(token),
       context: "api",
       user_id: user.id,
       expires_at: DateTime.truncate(expires_at, :second)
     }}
  end

  @doc "Builds a magic link token for an email."
  def build_magic_link_token(email) do
    token = :crypto.strong_rand_bytes(@rand_size)
    expires_at = DateTime.utc_now() |> DateTime.add(@magic_link_validity_minutes * 60)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: hash_token(token),
       context: "magic_link",
       sent_to: email,
       expires_at: DateTime.truncate(expires_at, :second)
     }}
  end

  @doc "Verifies a token string and returns the matching query."
  def verify_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed = hash_token(decoded_token)

        query =
          from t in __MODULE__,
            where: t.token == ^hashed and t.context == ^context,
            where: t.expires_at > ^DateTime.utc_now(),
            where: is_nil(t.used_at),
            join: u in assoc(t, :user),
            select: {u, t}

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Verifies a raw session token (binary, not base64)."
  def verify_session_token_query(token) do
    hashed = hash_token(token)

    query =
      from t in __MODULE__,
        where: t.token == ^hashed and t.context == "session",
        where: t.expires_at > ^DateTime.utc_now(),
        join: u in assoc(t, :user),
        select: u

    {:ok, query}
  end

  @doc "Verifies an API token (base64-encoded)."
  def verify_api_token_query(token) do
    verify_token_query(token, "api")
  end

  defp hash_token(token), do: :crypto.hash(@hash_algorithm, token)
end

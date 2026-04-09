defmodule Moth.Token do
  # Sqids requires a shuffled alphabet with no repeated characters.
  # We use the default alphabet which is already well-distributed.
  @sqids Sqids.new!(min_length: 8)

  def encode(token_ids) when is_list(token_ids) do
    Sqids.encode!(@sqids, token_ids)
  end

  def encode(token_id) when is_integer(token_id) do
    Sqids.encode!(@sqids, [token_id])
  end

  def decode(data) do
    Sqids.decode!(@sqids, data)
  end

  def suid() do
    [:positive]
    |> System.unique_integer()
    |> encode()
  end
end

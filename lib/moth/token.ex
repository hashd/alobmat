defmodule Moth.Token do
  @salt "___salt_cant_be_hardcoded_but___"
  @coder Hashids.new(salt: @salt, min_len: 8)
  @suid_options [:positive]

  def encode(token_ids) do
    Hashids.encode(@coder, token_ids)
  end

  def decode(data) do
    Hashids.decode(@coder, data)
  end

  def suid() do
    @suid_options
    |> System.unique_integer
    |> Moth.Token.encode
  end
end

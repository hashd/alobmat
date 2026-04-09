defmodule Moth.AuthFixtures do
  @moduledoc "Test helpers for creating auth entities."

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      name: "Test User",
      avatar_url: "https://example.com/avatar.png"
    })
  end
end

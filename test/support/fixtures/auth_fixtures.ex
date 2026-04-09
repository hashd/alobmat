defmodule Moth.AuthFixtures do
  @moduledoc "Test helpers for creating auth entities."

  alias Moth.Auth

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      name: "Test User",
      avatar_url: "https://example.com/avatar.png"
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Auth.register()

    user
  end
end

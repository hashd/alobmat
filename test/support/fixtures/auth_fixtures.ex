defmodule Moth.AuthFixtures do
  @moduledoc "Test helpers for creating auth entities."

  alias Moth.Auth

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def unique_user_phone, do: "+91#{Enum.random(6..9)}#{:rand.uniform(999_999_999) |> Integer.to_string() |> String.pad_leading(9, "0")}"

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

  def phone_user_fixture(attrs \\ %{}) do
    phone = attrs[:phone] || unique_user_phone()

    {:ok, user} =
      %Moth.Auth.User{}
      |> Moth.Auth.User.phone_registration_changeset(%{phone: phone, name: phone})
      |> Moth.Repo.insert()

    user
  end
end

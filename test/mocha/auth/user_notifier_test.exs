defmodule Mocha.Auth.UserNotifierTest do
  use Mocha.DataCase, async: true

  alias Mocha.Auth.UserNotifier

  test "deliver_magic_link/2 returns a Swoosh email" do
    email = "test@example.com"
    url = "http://localhost:4000/auth/magic/verify?token=abc123"

    assert {:ok, %Swoosh.Email{} = sent} = UserNotifier.deliver_magic_link(email, url)
    assert sent.to == [{"", email}]
    assert sent.subject =~ "Sign in to Mocha"
    assert sent.text_body =~ url
  end
end

defmodule Moth.Auth.UserNotifierTest do
  use Moth.DataCase, async: true

  alias Moth.Auth.UserNotifier

  test "deliver_magic_link/2 returns a Swoosh email" do
    email = "test@example.com"
    url = "http://localhost:4000/auth/magic/verify?token=abc123"

    assert {:ok, %Swoosh.Email{} = sent} = UserNotifier.deliver_magic_link(email, url)
    assert sent.to == [{"", email}]
    assert sent.subject =~ "Sign in to Moth"
    assert sent.text_body =~ url
  end
end

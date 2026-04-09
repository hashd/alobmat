defmodule Moth.Auth.UserNotifier do
  import Swoosh.Email

  alias Moth.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Moth", "noreply@moth.game"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  def deliver_magic_link(email, url) do
    deliver(email, "Sign in to Moth", """
    Hi,

    You can sign in to Moth by clicking the link below:

    #{url}

    This link expires in 15 minutes and can only be used once.

    If you didn't request this, you can safely ignore this email.
    """)
  end
end

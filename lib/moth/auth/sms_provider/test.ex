defmodule Moth.Auth.SMSProvider.Test do
  @moduledoc "Test adapter — sends message to calling process."
  @behaviour Moth.Auth.SMSProvider

  @impl true
  def deliver_otp(phone, code) do
    send(self(), {:otp_sent, phone, code})
    :ok
  end
end

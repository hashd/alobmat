defmodule Mocha.Auth.SMSProvider.Test do
  @moduledoc "Test adapter — sends message to calling process."
  @behaviour Mocha.Auth.SMSProvider

  @impl true
  def deliver_otp(phone, code) do
    send(self(), {:otp_sent, phone, code})
    :ok
  end
end

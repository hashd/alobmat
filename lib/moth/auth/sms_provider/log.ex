defmodule Moth.Auth.SMSProvider.Log do
  @moduledoc "Dev adapter — logs OTP to console."
  @behaviour Moth.Auth.SMSProvider

  require Logger

  @impl true
  def deliver_otp(phone, code) do
    Logger.info("[dev] OTP for #{phone}: #{code}")
    :ok
  end
end

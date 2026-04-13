defmodule Mocha.Auth.SMSProvider do
  @moduledoc "Behaviour for SMS delivery. Swapped per environment."

  @callback deliver_otp(phone :: String.t(), code :: String.t()) :: :ok | {:error, term()}

  def deliver_otp(phone, code) do
    impl().deliver_otp(phone, code)
  end

  defp impl do
    Application.get_env(:mocha, :sms_provider, Mocha.Auth.SMSProvider.Log)
  end
end

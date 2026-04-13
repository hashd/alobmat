defmodule Mocha.Auth.SMSProvider.MSG91 do
  @moduledoc "Production adapter — sends OTP via MSG91 HTTP API."
  @behaviour Mocha.Auth.SMSProvider

  require Logger

  @url "https://api.msg91.com/api/v5/otp"

  @impl true
  def deliver_otp(phone, code) do
    config = Application.get_env(:mocha, :msg91)
    auth_key = Keyword.fetch!(config, :auth_key)
    template_id = Keyword.fetch!(config, :template_id)

    # MSG91 expects mobile without leading '+'
    mobile = String.trim_leading(phone, "+")

    body =
      Jason.encode!(%{
        "authkey" => auth_key,
        "template_id" => template_id,
        "mobile" => mobile,
        "otp" => code
      })

    request =
      Finch.build(:post, @url, [{"Content-Type", "application/json"}], body)

    case Finch.request(request, Mocha.Finch) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        Logger.error("MSG91 OTP delivery failed: status=#{status} body=#{resp_body}")
        {:error, :sms_delivery_failed}

      {:error, reason} ->
        Logger.error("MSG91 OTP delivery error: #{inspect(reason)}")
        {:error, :sms_delivery_failed}
    end
  end
end

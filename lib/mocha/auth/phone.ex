defmodule Mocha.Auth.Phone do
  @moduledoc "Phone number normalization and validation for Indian mobile numbers."

  @indian_mobile_regex ~r/^\+91[6-9]\d{9}$/

  @doc """
  Normalizes a phone number to E.164 format (+91XXXXXXXXXX).

  Strips whitespace, dashes, parentheses. Prepends +91 if bare 10-digit Indian number.
  Only Indian mobile numbers (starting with 6/7/8/9) are accepted.

  Returns `{:ok, normalized}` or `{:error, :invalid_phone}`.
  """
  def normalize(nil), do: {:error, :invalid_phone}
  def normalize(""), do: {:error, :invalid_phone}

  def normalize(phone) when is_binary(phone) do
    cleaned =
      phone
      |> String.replace(~r/[\s\-\(\)]/, "")

    normalized =
      cond do
        String.starts_with?(cleaned, "+") ->
          cleaned

        String.starts_with?(cleaned, "91") and byte_size(cleaned) == 12 ->
          "+" <> cleaned

        byte_size(cleaned) == 10 ->
          "+91" <> cleaned

        true ->
          cleaned
      end

    if Regex.match?(@indian_mobile_regex, normalized) do
      {:ok, normalized}
    else
      {:error, :invalid_phone}
    end
  end

  def normalize(_), do: {:error, :invalid_phone}
end

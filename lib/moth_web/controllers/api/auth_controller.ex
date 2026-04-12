defmodule MothWeb.API.AuthController do
  use MothWeb, :controller

  alias Moth.Auth
  alias Moth.Auth.UserNotifier

  def request_magic_link(conn, %{"email" => email}) do
    email = String.downcase(String.trim(email))
    {token, _} = Auth.build_magic_link_token(email)
    url = url(~p"/auth/magic/verify?token=#{token}")
    UserNotifier.deliver_magic_link(email, url)
    json(conn, %{status: "ok", message: "Magic link sent"})
  end

  def verify_magic_link(conn, %{"token" => token}) do
    case Auth.verify_magic_link(token) do
      {:ok, user} ->
        {api_token, _} = Auth.generate_api_token(user)
        json(conn, %{token: api_token, user: user})

      :error ->
        conn
        |> put_status(401)
        |> json(%{error: %{code: "invalid_token", message: "Invalid or expired token"}})
    end
  end

  def refresh(conn, _params) do
    user = conn.assigns.current_user

    if user do
      {api_token, _} = Auth.generate_api_token(user)
      json(conn, %{token: api_token, user: user})
    else
      conn |> put_status(401) |> json(%{error: %{code: "unauthorized", message: "Invalid token"}})
    end
  end

  def logout(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def request_otp(conn, %{"phone" => phone}) do
    case Auth.request_phone_otp(phone) do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, :invalid_phone} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "invalid_phone", message: "Please enter a valid Indian mobile number"}})

      {:error, :rate_limited} ->
        conn
        |> put_status(429)
        |> json(%{error: %{code: "rate_limited", message: "Too many OTP requests. Please wait a few minutes."}})

      {:error, :sms_delivery_failed} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "sms_delivery_failed", message: "Could not send SMS. Please try again."}})
    end
  end

  def verify_otp(conn, %{"phone" => phone, "code" => code}) do
    case Auth.verify_phone_otp(phone, code) do
      {:ok, %{user: user, token: token, needs_name: needs_name}} ->
        json(conn, %{token: token, user: user, needs_name: needs_name})

      {:error, :invalid_phone} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "invalid_phone", message: "Please enter a valid Indian mobile number"}})

      {:error, :invalid_otp} ->
        conn
        |> put_status(401)
        |> json(%{error: %{code: "invalid_otp", message: "Invalid or expired code"}})

      {:error, :invalid_otp, attempts_remaining} ->
        conn
        |> put_status(401)
        |> json(%{error: %{code: "invalid_otp", message: "Wrong code", attempts_remaining: attempts_remaining}})

      {:error, :too_many_attempts} ->
        conn
        |> put_status(429)
        |> json(%{error: %{code: "too_many_attempts", message: "Too many wrong attempts. Please request a new code."}})
    end
  end

  if Application.compile_env(:moth, :dev_routes) do
    def dev_login(conn, params) do
      id = params["name"] || System.unique_integer([:positive]) |> to_string()
      email = "dev_#{id}@localhost"
      
      user =
        case Moth.Repo.get_by(Auth.User, email: email) do
          %Auth.User{} = u -> u
          nil -> 
            {:ok, u} = Auth.register(%{email: email, name: "Dev #{id}"})
            u
        end

      {api_token, _} = Auth.generate_api_token(user)
      json(conn, %{token: api_token, user: user})
    end
  end
end

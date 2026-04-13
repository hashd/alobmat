defmodule MochaWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :mocha

  @session_options [
    store: :cookie,
    key: "_mocha_key",
    signing_salt: "tambola_session",
    same_site: "Lax"
  ]

  socket "/socket", MochaWeb.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :mocha,
    gzip: false,
    only: MochaWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug MochaWeb.Router
end

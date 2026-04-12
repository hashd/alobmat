import Config

config :moth, MothWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "wD/QryEz4g+gbBX07rcqlOSa+1noaIinDCeuOlZRplMvuE9qx4NYRf6hNfPHPJMk",
  watchers: [
    node: [
      "node_modules/.bin/vite",
      cd: Path.expand("../assets", __DIR__)
    ]
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/moth_web/(controllers|channels)/.*(ex)$"
    ]
  ]

config :moth, Moth.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "moth_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :moth, dev_routes: true

config :swoosh, :api_client, false

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

config :moth, :sms_provider, Moth.Auth.SMSProvider.Log

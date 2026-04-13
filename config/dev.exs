import Config

config :mocha, MochaWeb.Endpoint,
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
      ~r"lib/mocha_web/(controllers|channels)/.*(ex)$"
    ]
  ]

config :mocha, Mocha.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mocha_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :mocha, dev_routes: true

config :swoosh, :api_client, false

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

config :mocha, :sms_provider, Mocha.Auth.SMSProvider.Log

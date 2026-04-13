import Config

config :mocha,
  ecto_repos: [Mocha.Repo]

config :mocha, MochaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MochaWeb.ErrorHTML, json: MochaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Mocha.PubSub,
  live_view: [signing_salt: "tambola_lv"]

config :mocha, Mocha.Mailer, adapter: Swoosh.Adapters.Local

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :game_id, :user_id]

config :phoenix, :json_library, Jason

# Assets are built by Vite (see assets/vite.config.ts)
# Tailwind is configured via assets/tailwind.config.js + PostCSS
config :tailwind, version: "4.1.12"

config :ueberauth, Ueberauth,
  base_path: "/auth",
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope: "email profile"
       ]}
  ]

import_config "#{config_env()}.exs"

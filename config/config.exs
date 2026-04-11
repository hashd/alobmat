import Config

config :moth,
  ecto_repos: [Moth.Repo]

config :moth, MothWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MothWeb.ErrorHTML, json: MothWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Moth.PubSub,
  live_view: [signing_salt: "tambola_lv"]

config :moth, Moth.Mailer, adapter: Swoosh.Adapters.Local

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :game_id, :user_id]

config :phoenix, :json_library, Jason

# Assets are built by Vite (see assets/vite.config.ts)
# Tailwind is configured via assets/tailwind.config.js + PostCSS

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

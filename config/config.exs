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

config :esbuild,
  version: "0.17.11",
  default: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.0",
  moth: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :ueberauth, Ueberauth,
  base_path: "/auth",
  providers: [
    google: {Ueberauth.Strategy.Google, [
      default_scope: "email profile"
    ]}
  ]

import_config "#{config_env()}.exs"

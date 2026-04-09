# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
import Config

# General application configuration
config :moth,
  ecto_repos: [Moth.Repo]

# Configures the endpoint
config :moth, MothWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: MothWeb.ErrorHTML, json: MothWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Moth.PubSub,
  live_view: [signing_salt: "tambola_lv"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Ueberauth Config for oauth
config :ueberauth, Ueberauth,
  base_path: "/auth",
  providers: [
    google: {Ueberauth.Strategy.Google, [
      default_scope: "email profile",
      hd: "*",
      access_type: "offline"
    ]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :moth,
  ecto_repos: [Moth.Repo]

# Configures the endpoint
config :moth, MothWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "wD/QryEz4g+gbBX07rcqlOSa+1noaIinDCeuOlZRplMvuE9qx4NYRf6hNfPHPJMk",
  render_errors: [view: MothWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Moth.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Ueberauth Config for oauth
config :ueberauth, Ueberauth,
  base_path: "/auth",
  providers: [
    google: { Ueberauth.Strategy.Google, [
      default_scope: "email profile",
      hd: "*",
      approval_prompt: "force",
      access_type: "offline"
    ]}
  ]

# Ueberauth Strategy Config for Google oauth
config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

# Guardian configuration
config :guardian, Moth.Guardian,
  allowed_algos: ["HS512"], # optional
  verify_module: Guardian.JWT,  # optional
  issuer: "MothServer",
  ttl: { 30, :days },
  allowed_drift: 2000,
  verify_issuer: true, # optional
  secret_key: System.get_env("GUARDIAN_SECRET") || "wD/QryEz4g+gbBX07rcqlOSa+1noaIinDCeuOlZRplMvuE9qx4NYRf6hNfPHPJMk"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"

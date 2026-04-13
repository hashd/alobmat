import Config

config :mocha, MochaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test_secret_key_base_that_is_at_least_64_bytes_long_for_testing_purposes_only",
  server: false

config :mocha, Mocha.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mocha_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :mocha, Mocha.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :logger, level: :warning

config :mocha, :sms_provider, Mocha.Auth.SMSProvider.Test

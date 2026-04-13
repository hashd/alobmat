defmodule Mocha.Repo do
  use Ecto.Repo,
    otp_app: :mocha,
    adapter: Ecto.Adapters.Postgres
end

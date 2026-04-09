defmodule Moth.Repo do
  use Ecto.Repo,
    otp_app: :moth,
    adapter: Ecto.Adapters.Postgres
end

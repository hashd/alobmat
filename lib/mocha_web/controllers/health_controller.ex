defmodule MochaWeb.HealthController do
  use MochaWeb, :controller

  def check(conn, _params) do
    Mocha.Repo.query!("SELECT 1")
    json(conn, %{status: "ok"})
  rescue
    _ -> conn |> put_status(503) |> json(%{status: "unhealthy"})
  end
end

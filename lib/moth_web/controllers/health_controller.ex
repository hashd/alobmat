defmodule MothWeb.HealthController do
  use MothWeb, :controller

  def check(conn, _params) do
    Moth.Repo.query!("SELECT 1")
    json(conn, %{status: "ok"})
  rescue
    _ -> conn |> put_status(503) |> json(%{status: "unhealthy"})
  end
end

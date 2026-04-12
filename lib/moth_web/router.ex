defmodule MothWeb.Router do
  use MothWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MothWeb.Plugs.Auth

    if Application.compile_env(:moth, :dev_routes) do
      plug MothWeb.Plugs.DevAuth
    end
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug
    plug MothWeb.Plugs.APIAuth
  end

  pipeline :require_auth do
    plug :require_authenticated_user
  end

  pipeline :require_api_auth do
    plug MothWeb.Plugs.APIAuth, :require_api_auth
  end

  # Mobile API (unauthenticated)
  scope "/api", MothWeb.API do
    pipe_through :api

    post "/auth/magic", AuthController, :request_magic_link
    post "/auth/verify", AuthController, :verify_magic_link
    post "/auth/oauth/:provider", AuthController, :oauth
    post "/auth/refresh", AuthController, :refresh
    delete "/auth/session", AuthController, :logout

    if Application.compile_env(:moth, :dev_routes) do
      post "/auth/dev", AuthController, :dev_login
    end
  end

  # Mobile API (authenticated)
  scope "/api", MothWeb.API do
    pipe_through [:api, :require_api_auth]

    get "/user/me", UserController, :show
    patch "/user/me", UserController, :update

    get "/games", GameController, :recent
    get "/games/public", GameController, :public_games
    post "/games", GameController, :create
    get "/games/:code", GameController, :show
    post "/games/:code/clone", GameController, :clone
    post "/games/:code/join", GameController, :join
    post "/games/:code/start", GameController, :start
    post "/games/:code/pause", GameController, :pause
    post "/games/:code/resume", GameController, :resume
    post "/games/:code/end", GameController, :end_game
    post "/games/:code/strike_out", GameController, :strike_out
    post "/games/:code/claim", GameController, :claim
    put "/games/:code/players/:user_id/ticket_count", GameController, :set_ticket_count
  end

  # LiveDashboard (dev only)
  if Application.compile_env(:moth, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: MothWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Web routes — browser scope with SPA catch-all last so it doesn't shadow API routes
  scope "/", MothWeb do
    pipe_through :browser

    get "/auth/:provider", AuthController, :request
    get "/auth/:provider/callback", AuthController, :callback
    delete "/auth/logout", AuthController, :logout
    get "/auth/magic/verify", AuthController, :verify_magic_link

    # SPA catch-all — must be the very last route
    get "/*path", PageController, :spa
  end

  defp require_authenticated_user(conn, _opts) do
    MothWeb.Plugs.Auth.require_authenticated_user(conn, [])
  end
end

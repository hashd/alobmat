defmodule MothWeb.Router do
  use MothWeb, :router

  require Ueberauth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MothWeb.Plug.SetUser
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug MothWeb.Plug.SetUser
  end

  scope "/api", MothWeb.API do
    pipe_through :api

    get   "/auth/token", AuthController, :token
    get   "/games/:id",  GameController, :show
    post  "/games/",     GameController, :new
  end

  scope "/auth", MothWeb do
    pipe_through :browser

    get "/logout", AuthController, :log_out
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/", MothWeb do
    pipe_through :browser # Use the default browser stack

    get "/", BaseController, :index
    get "/games/:id", GameController, :index
  end
end

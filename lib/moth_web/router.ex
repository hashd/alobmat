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

  pipeline :authenticated_api do
    plug MothWeb.Plug.CheckAPIAuth
  end

  scope "/api", MothWeb.API do
    pipe_through :api
    pipe_through :authenticated_api

    get   "/users",       UserController, :index
    get   "/auth/token",  AuthController, :token
    post  "/games",       GameController, :new
  end

  scope "/api", MothWeb.API do
    pipe_through :api

    get   "/games",       GameController, :index
    get   "/games/:id",   GameController, :show
  end

  scope "/auth", MothWeb do
    pipe_through :browser

    get   "/logout",      AuthController, :log_out
    get   "/:provider",   AuthController, :request
    get   "/:provider/callback", AuthController, :callback
  end

  scope "/", MothWeb do
    pipe_through :browser

    get "/",              BaseController, :index
  end
end

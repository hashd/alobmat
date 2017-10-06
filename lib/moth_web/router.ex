defmodule MothWeb.Router do
  use MothWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MothWeb.API do
    pipe_through :api

    get  "/games/:id", GameController, :show
    post "/games/:id", GameController, :new

    scope "/auth" do
      get "/:provider", AuthController, :request
      get "/:provider", AuthController, :callback
      delete "/logout", AuthController, :log_out
    end
  end

  scope "/", MothWeb do
    pipe_through :browser # Use the default browser stack

    get "/", BaseController, :index
    get "/games/:id", GameController, :index
  end
end

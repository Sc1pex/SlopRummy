defmodule RemybunWeb.Router do
  use RemybunWeb, :router

  import RemybunWeb.Plugs.Auth, only: [require_user: 2]

  pipeline :api do
    plug :accepts, ["json"]
    plug RemybunWeb.Plugs.Auth
  end

  pipeline :authenticated do
    plug :require_user
  end

  scope "/api", RemybunWeb do
    pipe_through :api

    post "/guest", AuthController, :guest
    post "/register", AuthController, :register
    post "/login", AuthController, :login
  end

  scope "/api", RemybunWeb do
    pipe_through [:api, :authenticated]

    delete "/logout", AuthController, :logout
    get "/me", AuthController, :me
  end
end

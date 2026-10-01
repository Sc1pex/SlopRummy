defmodule RemybunWeb.Router do
  use RemybunWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", RemybunWeb do
    pipe_through :api
  end
end

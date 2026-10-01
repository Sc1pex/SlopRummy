defmodule RemybunWeb.AuthController do
  use RemybunWeb, :controller

  alias Remybun.Accounts
  alias RemybunWeb.UserJSON

  action_fallback RemybunWeb.FallbackController

  def guest(conn, _params) do
    with {:ok, user} <- Accounts.create_guest() do
      conn
      |> put_status(:created)
      |> json(UserJSON.auth(%{user: user, token: Accounts.create_api_token(user)}))
    end
  end

  def register(conn, params) do
    attrs = Map.take(params, ["username", "email", "password"])

    with {:ok, user} <- Accounts.register(attrs, conn.assigns.current_user) do
      # An upgraded guest keeps their existing token.
      token =
        if conn.assigns.current_user,
          do: conn.assigns.current_token,
          else: Accounts.create_api_token(user)

      conn |> put_status(:created) |> json(UserJSON.auth(%{user: user, token: token}))
    end
  end

  def login(conn, params) do
    with {:ok, user} <- Accounts.authenticate(params["email"], params["password"]) do
      json(conn, UserJSON.auth(%{user: user, token: Accounts.create_api_token(user)}))
    end
  end

  def logout(conn, _params) do
    Accounts.delete_api_token(conn.assigns.current_token)
    send_resp(conn, :no_content, "")
  end

  def me(conn, _params), do: json(conn, UserJSON.show(%{user: conn.assigns.current_user}))
end

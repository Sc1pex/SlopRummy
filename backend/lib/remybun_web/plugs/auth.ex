defmodule RemybunWeb.Plugs.Auth do
  @moduledoc """
  Reads `Authorization: Bearer <token>` and assigns `:current_user` and `:current_token`.
  Use `require_user/2` to reject unauthenticated requests.
  """
  import Plug.Conn

  alias Remybun.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %Accounts.User{} = user <- Accounts.get_user_by_api_token(token) do
      conn |> assign(:current_user, user) |> assign(:current_token, token)
    else
      _ -> conn |> assign(:current_user, nil) |> assign(:current_token, nil)
    end
  end

  def require_user(%{assigns: %{current_user: %Accounts.User{}}} = conn, _opts), do: conn

  def require_user(conn, _opts) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "unauthorized"})
    |> halt()
  end
end

defmodule RemybunWeb.UserSocket do
  use Phoenix.Socket

  alias Remybun.Accounts

  channel "lobby", RemybunWeb.LobbyChannel
  channel "table:*", RemybunWeb.TableChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Accounts.get_user_by_api_token(token) do
      nil -> :error
      user -> {:ok, assign(socket, :current_user, user)}
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "users_socket:#{socket.assigns.current_user.id}"
end

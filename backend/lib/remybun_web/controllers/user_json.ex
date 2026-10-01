defmodule RemybunWeb.UserJSON do
  alias Remybun.Accounts.User

  def user(%User{} = u), do: %{id: u.id, username: u.username, email: u.email, guest: u.guest}

  def auth(%{user: user, token: token}), do: %{user: user(user), token: token}
  def show(%{user: user}), do: %{user: user(user)}
end

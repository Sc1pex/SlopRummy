defmodule RemybunWeb.ChannelCase do
  @moduledoc """
  Test case for channel tests. Runs with a shared DB sandbox (table servers are
  separate processes), so these tests are not async.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import RemybunWeb.ChannelCase

      @endpoint RemybunWeb.Endpoint
    end
  end

  setup _tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Remybun.Repo, shared: true)

    on_exit(fn ->
      for {_, child, _, _} <- DynamicSupervisor.which_children(Remybun.Tables.Supervisor) do
        DynamicSupervisor.terminate_child(Remybun.Tables.Supervisor, child)
      end

      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)

    :ok
  end

  def user_fixture(name) do
    {:ok, user} =
      Remybun.Accounts.register(%{
        username: name,
        email: "#{name}@example.com",
        password: "supersecret"
      })

    user
  end

  def socket_for(user) do
    token = Remybun.Accounts.create_api_token(user)

    {:ok, socket} =
      Phoenix.ChannelTest.__connect__(
        RemybunWeb.Endpoint,
        RemybunWeb.UserSocket,
        %{"token" => token},
        []
      )

    socket
  end
end

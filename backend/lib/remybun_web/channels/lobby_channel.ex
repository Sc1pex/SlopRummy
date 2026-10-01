defmodule RemybunWeb.LobbyChannel do
  @moduledoc """
  Lists public tables (`table_updated`, `table_closed` pushes) and tracks who is online.
  """
  use RemybunWeb, :channel

  alias Remybun.Tables
  alias Remybun.Tables.TableServer
  alias RemybunWeb.Presence

  @impl true
  def join("lobby", _params, socket) do
    Phoenix.PubSub.subscribe(Remybun.PubSub, TableServer.lobby_topic())
    send(self(), :after_join)
    {:ok, %{tables: Tables.list_public()}, socket}
  end

  @impl true
  def handle_info(:after_join, socket) do
    user = socket.assigns.current_user

    {:ok, _} =
      Presence.track(socket, user.id, %{
        username: user.username,
        guest: user.guest,
        online_at: System.system_time(:second)
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  def handle_info({:table_summary, summary}, socket) do
    push(socket, "table_updated", summary)
    {:noreply, socket}
  end

  def handle_info({:table_closed, code}, socket) do
    push(socket, "table_closed", %{code: code})
    {:noreply, socket}
  end
end

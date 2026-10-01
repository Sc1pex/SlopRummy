defmodule Remybun.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      RemybunWeb.Telemetry,
      Remybun.Repo,
      {DNSCluster, query: Application.get_env(:remybun, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Remybun.PubSub},
      RemybunWeb.Presence,
      {Registry, keys: :unique, name: Remybun.Tables.Registry},
      {DynamicSupervisor, name: Remybun.Tables.Supervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      RemybunWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Remybun.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RemybunWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

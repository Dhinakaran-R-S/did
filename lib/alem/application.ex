defmodule Alem.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Ensure the local data directory exists before the repo starts
    data_dir = Application.get_env(:alem, :local_first_data_dir, "priv/local_data")
    File.mkdir_p!(data_dir)

    children = [
      AlemWeb.Telemetry,
      # Primary PostgreSQL repo
      Alem.Repo,
      # Server-side SQLite repo for local-first offline queue & metadata
      Alem.LocalFirst.LibSQLRepo,
      {Phoenix.PubSub, name: Alem.PubSub},
      {DNSCluster, query: Application.get_env(:alem, :dns_cluster_query) || :ignore},
      {Finch, name: Alem.Finch},
      # Horde for distributed namespaces
      {Horde.Registry,
       name: Alem.Namespace.HordeRegistry, keys: :unique, members: :auto},
      {Horde.DynamicSupervisor,
       name: Alem.Namespace.DynamicSupervisor,
       strategy: :one_for_one,
       members: :auto},
      # Registry for SyncManager processes
      {Registry, keys: :unique, name: Alem.LocalFirst.SyncRegistry},
      AlemWeb.Endpoint
    ]

    children =
      if Application.get_env(:alem, :dev_routes, false) do
        children ++ [{Alem.PleromaMockServer, [port: 4001]}]
      else
        children
      end

    opts = [strategy: :one_for_one, name: Alem.Supervisor]

    Task.start(fn -> Alem.LocalFirst.SqldSchema.setup() end)

    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AlemWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

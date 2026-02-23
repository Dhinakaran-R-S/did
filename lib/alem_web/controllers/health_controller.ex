defmodule AlemWeb.HealthController do
  use AlemWeb, :controller
  require Logger
  alias Alem.Repo

  def check(conn, _params) do
    services = check_services()
    overall = if all_healthy?(services), do: :ok, else: :service_unavailable
    conn
    |> put_status(overall)
    |> json(%{
      status: if(overall == :ok, do: "ok", else: "degraded"),
      timestamp: DateTime.utc_now(),
      version: Application.spec(:alem, :vsn) |> to_string(),
      services: services
    })
  end

  defp check_services do
    %{
      database:       check_database(),
      libsql:         check_libsql(),
      object_storage: check_object_storage(),
      couchdb:        check_couchdb(),
      horde:          check_horde()
    }
  end

  defp check_database do
    case Repo.query("SELECT 1", []) do
      {:ok, _}        -> %{status: "healthy", message: "PostgreSQL OK"}
      {:error, reason}-> %{status: "unhealthy", message: inspect(reason)}
    end
  rescue
    e -> %{status: "unhealthy", message: inspect(e)}
  end

  defp check_libsql do
    case Code.ensure_loaded(Alem.LocalFirst.LibSQLRepo) do
      {:module, _}    -> %{status: "healthy", message: "LibSQL module loaded"}
      {:error, reason}-> %{status: "unhealthy", message: inspect(reason)}
    end
  rescue
    e -> %{status: "unhealthy", message: inspect(e)}
  end

  defp check_object_storage do
    bucket = Application.get_env(:alem, :file_storage)[:bucket]
    # list/2 — (bucket, prefix).  No third argument.
    case Alem.Storage.ObjectStore.list(bucket, "") do
      {:ok, _}        -> %{status: "healthy", message: "Object storage accessible"}
      {:error, reason}-> %{status: "unhealthy", message: inspect(reason)}
    end
  rescue
    e -> %{status: "unhealthy", message: inspect(e)}
  end

  defp check_couchdb do
    case Alem.Storage.DocumentStore.ensure_database("health_check") do
      :ok             -> %{status: "healthy", message: "CouchDB accessible"}
      {:error, reason}-> %{status: "unhealthy", message: inspect(reason)}
    end
  rescue
    e -> %{status: "unhealthy", message: inspect(e)}
  end

  defp check_horde do
    count = Horde.Registry.count(Alem.Namespace.HordeRegistry)
    %{status: "healthy", message: "Horde registry active", registrations: count}
  rescue
    e -> %{status: "unhealthy", message: inspect(e)}
  end

  defp all_healthy?(services) do
    Enum.all?(services, fn {_k, v} -> v[:status] == "healthy" end)
  end
end

defmodule AlemWeb.SyncController do
  use AlemWeb, :controller
  require Logger

  import Ecto.Query
  alias Alem.Repo
  alias Alem.Schemas.{Document, Namespace}

  plug AlemWeb.Plugs.PleromaAuth

  def get_changes(conn, params) do
    user_id = conn.assigns.pleroma_account_id
    since   = parse_timestamp(params["since"])
    limit   = String.to_integer(params["limit"] || "100")

    # get_user_changes always returns {:ok, list} — no error branch
    {:ok, changes} = get_user_changes(user_id, since, limit)

    conn
    |> json(%{
      changes:   changes,
      timestamp: DateTime.utc_now(),
      has_more:  length(changes) >= limit
    })
  end

  def apply_changes(conn, params) do
    user_id = conn.assigns.pleroma_account_id
    changes = params["changes"] || []

    {:ok, results} = apply_client_changes(user_id, changes)

    conn
    |> json(%{
      message:       "Changes applied",
      results:       results,
      applied_count: Enum.count(results, &(&1["status"] == "applied")),
      failed_count:  Enum.count(results, &(&1["status"] == "failed")),
      timestamp:     DateTime.utc_now()
    })
  end

  defp parse_timestamp(nil), do: DateTime.add(DateTime.utc_now(), -30, :day)
  defp parse_timestamp(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _            -> DateTime.add(DateTime.utc_now(), -30, :day)
    end
  end

  @spec get_user_changes(String.t(), DateTime.t(), pos_integer()) :: {:ok, list()}
  defp get_user_changes(user_id, since, limit) do
    docs = get_document_changes(user_id, since, limit)
    nss  = get_namespace_changes(user_id, since)
    all  = (docs ++ nss) |> Enum.sort_by(& &1["timestamp"], {:desc, DateTime}) |> Enum.take(limit)
    {:ok, all}
  end

  defp get_document_changes(user_id, since, limit) do
    from(d in Document,
      where: d.user_id == ^user_id and d.updated_at > ^since,
      order_by: [desc: d.updated_at],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn d ->
      %{"type" => "document_updated", "id" => d.id, "timestamp" => d.updated_at,
        "data" => %{"id" => d.id, "filename" => d.filename, "content_type" => d.content_type,
                    "object_key" => d.object_key, "content_hash" => d.content_hash,
                    "metadata" => d.metadata, "status" => d.status, "updated_at" => d.updated_at}}
    end)
  end

  defp get_namespace_changes(user_id, since) do
    from(n in Namespace,
      where: n.id == ^user_id and n.updated_at > ^since,
      order_by: [desc: n.updated_at]
    )
    |> Repo.all()
    |> Enum.map(fn n ->
      %{"type" => "namespace_updated", "id" => n.id, "timestamp" => n.updated_at,
        "data" => %{"id" => n.id, "tenant_id" => n.tenant_id, "did" => n.did,
                    "config" => n.config, "status" => n.status, "updated_at" => n.updated_at}}
    end)
  end

  @spec apply_client_changes(String.t(), list()) :: {:ok, list(map())}
  defp apply_client_changes(user_id, changes) do
    results = Enum.map(changes, fn change ->
      case apply_single_change(user_id, change) do
        {:ok, result}    -> %{"change_id" => change["id"], "status" => "applied", "result" => result}
        {:error, reason} ->
          Logger.error("[SyncController] change #{change["id"]} failed: #{inspect(reason)}")
          %{"change_id" => change["id"], "status" => "failed", "error" => inspect(reason)}
      end
    end)
    {:ok, results}
  end

  defp apply_single_change(user_id, change) do
    case change["type"] do
      "create_document" -> create_document_from_change(user_id, change["data"])
      "update_document" -> update_document_from_change(user_id, change["data"])
      "delete_document" -> delete_document_from_change(user_id, change["data"])
      type ->
        Logger.warning("[SyncController] Unknown change type: #{type}")
        {:ok, :skipped}
    end
  end

  defp create_document_from_change(user_id, data) do
    if data["user_id"] != user_id do
      {:error, :unauthorized}
    else
      result = Repo.insert(Document.changeset(%Document{}, %{
        id: data["id"], user_id: user_id,
        tenant_id: data["tenant_id"] || "default",
        filename: data["filename"], content_type: data["content_type"],
        object_key: data["object_key"], content_hash: data["content_hash"],
        text_content: data["text_content"], metadata: data["metadata"] || %{},
        status: "completed"
      }))

      case result do
        {:ok, doc}        -> {:ok, %{"id" => doc.id, "status" => "created"}}
        {:error, _} = err -> err
      end
    end
  end

  defp update_document_from_change(user_id, data) do
    case Repo.get(Document, data["id"]) do
      nil                           -> {:error, :not_found}
      %Document{user_id: ^user_id} = doc ->
        result = Repo.update(Document.changeset(doc, %{
          filename: data["filename"], content_type: data["content_type"],
          text_content: data["text_content"], metadata: data["metadata"] || %{}
        }))

        case result do
          {:ok, d}          -> {:ok, %{"id" => d.id, "status" => "updated"}}
          {:error, _} = err -> err
        end
      %Document{} -> {:error, :unauthorized}
    end
  end

  defp delete_document_from_change(user_id, data) do
    case Repo.get(Document, data["id"]) do
      nil                           -> {:error, :not_found}
      %Document{user_id: ^user_id} = doc ->
        case Repo.delete(doc) do
          {:ok, _}          -> {:ok, %{"id" => doc.id, "status" => "deleted"}}
          {:error, _} = err -> err
        end
      %Document{} -> {:error, :unauthorized}
    end
  end
end

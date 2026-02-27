defmodule AlemWeb.SyncController do
  use AlemWeb, :controller
  require Logger

  import Ecto.Query
  alias Alem.Repo
  alias Alem.Schemas.{Document, Namespace}
  alias Alem.Storage.ObjectStore

  plug AlemWeb.Plugs.PleromaAuth

  @sqld_url "http://172.235.17.68:8080"
  @bucket   "perkeep"

  # ── Schema bootstrap ────────────────────────────────────────────────────────
  # Call once on startup to ensure sqld has the documents table.
  def ensure_sqld_schema do
    sql = """
    CREATE TABLE IF NOT EXISTS documents (
      id           TEXT PRIMARY KEY,
      user_id      TEXT NOT NULL,
      tenant_id    TEXT NOT NULL DEFAULT 'default',
      filename     TEXT NOT NULL,
      content_type TEXT,
      object_key   TEXT,
      content_hash TEXT,
      text_content TEXT,
      metadata     TEXT DEFAULT '{}',
      status       TEXT DEFAULT 'completed',
      inserted_at  TEXT NOT NULL,
      updated_at   TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_documents_user_id  ON documents (user_id);
    CREATE INDEX IF NOT EXISTS idx_documents_updated  ON documents (updated_at);
    """

    sqld_execute(sql)
  end

  # ── get_upload_url ──────────────────────────────────────────────────────────
  # Returns a real S3 presigned PUT URL so Tauri uploads directly to Linode S3.
  def get_upload_url(conn, params) do
    user_id  = conn.assigns.pleroma_account_id
    doc_id   = params["doc_id"]
    filename = params["filename"]

    object_key = "uploads/#{user_id}/#{doc_id}/#{filename}"

    case ObjectStore.presigned_upload_url(@bucket, object_key, expires_in: 3600) do
      {:ok, presigned_url} ->
        Logger.info("[SyncController] Generated presigned URL for #{object_key}")
        conn |> json(%{upload_url: presigned_url, object_key: object_key})

      {:error, reason} ->
        Logger.error("[SyncController] Failed to generate presigned URL: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{error: "Failed to generate upload URL"})
    end
  end

  # ── upload_file ─────────────────────────────────────────────────────────────
  # Fallback direct upload if presigned URL fails — Phoenix proxies to S3.
  def upload_file(conn, %{"doc_id" => doc_id} = params) do
    user_id    = conn.assigns.pleroma_account_id
    filename   = params["filename"] || "file"
    object_key = "uploads/#{user_id}/#{doc_id}/#{filename}"

    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_073_741_824)

    content_type = conn
      |> Plug.Conn.get_req_header("content-type")
      |> List.first() || "application/octet-stream"

    case ObjectStore.put(@bucket, object_key, body, %{content_type: content_type}) do
      :ok ->
        Logger.info("[SyncController] Direct upload OK: #{object_key}")
        conn |> json(%{status: "uploaded", object_key: object_key})

      {:error, reason} ->
        Logger.error("[SyncController] Direct upload failed: #{inspect(reason)}")
        conn |> put_status(500) |> json(%{error: inspect(reason)})
    end
  end

  # ── apply_changes ───────────────────────────────────────────────────────────
  # Writes metadata to BOTH PostgreSQL and sqld.
  def apply_changes(conn, params) do
    user_id = conn.assigns.pleroma_account_id
    changes = params["changes"] || []

    Logger.info("[SyncController] apply_changes user_id=#{user_id} count=#{length(changes)}")

    {:ok, results} = apply_client_changes(user_id, changes)

    conn |> json(%{
      message:       "Changes applied",
      results:       results,
      applied_count: Enum.count(results, &(&1["status"] == "applied")),
      failed_count:  Enum.count(results, &(&1["status"] == "failed")),
      timestamp:     DateTime.utc_now()
    })
  end

  # ── get_changes ─────────────────────────────────────────────────────────────
  # Reads from sqld as primary source, falls back to PostgreSQL.
  def get_changes(conn, params) do
    user_id = conn.assigns.pleroma_account_id
    since   = parse_timestamp(params["since"])
    limit   = String.to_integer(params["limit"] || "100")

    {:ok, changes} = get_user_changes(user_id, since, limit)

    conn |> json(%{
      changes:   changes,
      timestamp: DateTime.utc_now(),
      has_more:  length(changes) >= limit
    })
  end

  # ── Private — change application ─────────────────────────────────────────────

  defp apply_client_changes(user_id, changes) do
    results = Enum.map(changes, fn change ->
      case apply_single_change(user_id, change) do
        {:ok, result} ->
          %{"change_id" => change["id"], "status" => "applied", "result" => result}
        {:error, reason} ->
          Logger.error("[SyncController] change #{change["id"]} failed: #{inspect(reason)}")
          %{"change_id" => change["id"], "status" => "failed", "error" => inspect(reason)}
      end
    end)
    {:ok, results}
  end

  defp apply_single_change(user_id, change) do
    case change["type"] do
      "create_document" -> create_document(user_id, change["data"])
      "update_document" -> update_document(user_id, change["data"])
      "delete_document" -> delete_document(user_id, change["data"])
      type ->
        Logger.warning("[SyncController] Unknown change type: #{type}")
        {:ok, :skipped}
    end
  end

  # ── create_document ──────────────────────────────────────────────────────────

  defp create_document(user_id, data) do
    now = DateTime.utc_now()

    attrs = %{
      id:           data["id"],
      user_id:      user_id,
      tenant_id:    data["tenant_id"] || "default",
      filename:     data["filename"],
      content_type: data["content_type"],
      object_key:   data["object_key"],
      content_hash: data["content_hash"],
      text_content: data["text_content"],
      metadata:     data["metadata"] || %{},
      status:       "completed"
    }

    # Use insert_or_ignore to handle duplicate IDs gracefully
    pg_result = Repo.insert(
      Document.changeset(%Document{}, attrs),
      on_conflict: :replace_all,
      conflict_target: :id
    )

    sqld_result = sqld_upsert_document(attrs, now)

    case {pg_result, sqld_result} do
      {{:ok, doc}, :ok} ->
        Logger.info("[SyncController] Document #{doc.id} saved to PG + sqld")
        {:ok, %{"id" => doc.id, "status" => "created"}}

      {{:ok, doc}, {:error, sqld_err}} ->
        Logger.warning("[SyncController] Document #{doc.id} saved to PG but sqld failed: #{inspect(sqld_err)}")
        {:ok, %{"id" => doc.id, "status" => "created_pg_only"}}

      {{:error, reason}, _} ->
        Logger.error("[SyncController] PG insert failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ── update_document ──────────────────────────────────────────────────────────

  defp update_document(user_id, data) do
    now = DateTime.utc_now()

    case Repo.get(Document, data["id"]) do
      nil ->
        {:error, :not_found}

      %Document{user_id: ^user_id} = doc ->
        attrs = %{
          filename:     data["filename"],
          content_type: data["content_type"],
          object_key:   data["object_key"] || doc.object_key,
          text_content: data["text_content"],
          metadata:     data["metadata"] || %{}
        }

        pg_result   = Repo.update(Document.changeset(doc, attrs))
        sqld_result = sqld_upsert_document(Map.merge(attrs, %{id: doc.id, user_id: user_id, tenant_id: doc.tenant_id}), now)

        case pg_result do
          {:ok, d} ->
            Logger.info("[SyncController] Document #{d.id} updated. sqld: #{inspect(sqld_result)}")
            {:ok, %{"id" => d.id, "status" => "updated"}}
          err -> err
        end

      %Document{} ->
        {:error, :unauthorized}
    end
  end

  # ── delete_document ──────────────────────────────────────────────────────────

  defp delete_document(user_id, data) do
    doc_id = data["id"]

    case Repo.get(Document, doc_id) do
      nil ->
        sqld_delete_document(doc_id)
        {:ok, %{"id" => doc_id, "status" => "not_found"}}

      %Document{user_id: ^user_id} = doc ->
        Repo.delete(doc)
        sqld_delete_document(doc_id)
        {:ok, %{"id" => doc_id, "status" => "deleted"}}

      %Document{} ->
        {:error, :unauthorized}
    end
  end

  # ── get_user_changes ─────────────────────────────────────────────────────────

  defp get_user_changes(user_id, since, limit) do
    # Try sqld first
    case sqld_get_document_changes(user_id, since, limit) do
      {:ok, docs} when length(docs) >= 0 ->
        nss = get_namespace_changes(user_id, since)
        all = (docs ++ nss)
              |> Enum.sort_by(& &1["timestamp"], {:desc, DateTime})
              |> Enum.take(limit)
        {:ok, all}

      {:error, reason} ->
        Logger.warning("[SyncController] sqld query failed, falling back to PG: #{inspect(reason)}")
        docs = get_document_changes_from_pg(user_id, since, limit)
        nss  = get_namespace_changes(user_id, since)
        all  = (docs ++ nss)
               |> Enum.sort_by(& &1["timestamp"], {:desc, DateTime})
               |> Enum.take(limit)
        {:ok, all}
    end
  end

  # ── sqld helpers ─────────────────────────────────────────────────────────────

  defp sqld_upsert_document(attrs, now) do
    now_str = DateTime.to_iso8601(now)
    meta    = Jason.encode!(attrs[:metadata] || attrs["metadata"] || %{})
    id      = attrs[:id] || attrs["id"]

    sql = """
    INSERT INTO documents (id, user_id, tenant_id, filename, content_type,
      object_key, content_hash, text_content, metadata, status, inserted_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      filename     = excluded.filename,
      content_type = excluded.content_type,
      object_key   = COALESCE(excluded.object_key, object_key),
      content_hash = COALESCE(excluded.content_hash, content_hash),
      text_content = excluded.text_content,
      metadata     = excluded.metadata,
      status       = excluded.status,
      updated_at   = excluded.updated_at
    """

    args = [
      id,
      attrs[:user_id]      || attrs["user_id"],
      attrs[:tenant_id]    || attrs["tenant_id"] || "default",
      attrs[:filename]     || attrs["filename"],
      attrs[:content_type] || attrs["content_type"],
      attrs[:object_key]   || attrs["object_key"],
      attrs[:content_hash] || attrs["content_hash"],
      attrs[:text_content] || attrs["text_content"],
      meta,
      attrs[:status]       || attrs["status"] || "completed",
      now_str,
      now_str
    ]

    sqld_execute(sql, args)
  end

  defp sqld_delete_document(doc_id) do
    sqld_execute("DELETE FROM documents WHERE id = ?", [doc_id])
  end

  defp sqld_get_document_changes(user_id, since, limit) do
    since_str = DateTime.to_iso8601(since)

    sql = """
    SELECT id, user_id, tenant_id, filename, content_type, object_key,
           content_hash, text_content, metadata, status, updated_at
    FROM documents
    WHERE user_id = ? AND updated_at > ?
    ORDER BY updated_at DESC
    LIMIT ?
    """

    case sqld_query(sql, [user_id, since_str, limit]) do
      {:ok, rows} ->
        docs = Enum.map(rows, fn row ->
          [id, uid, tid, fname, ct, ok, ch, tc, meta, status, updated] = row
          %{
            "type"      => "document_updated",
            "id"        => id,
            "timestamp" => parse_sqld_timestamp(updated),
            "data"      => %{
              "id"           => id,
              "user_id"      => uid,
              "tenant_id"    => tid,
              "filename"     => fname,
              "content_type" => ct,
              "object_key"   => ok,
              "content_hash" => ch,
              "text_content" => tc,
              "metadata"     => decode_metadata(meta),
              "status"       => status,
              "updated_at"   => updated
            }
          }
        end)
        {:ok, docs}

      error -> error
    end
  end

  defp get_document_changes_from_pg(user_id, since, limit) do
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

  # ── sqld HTTP client ─────────────────────────────────────────────────────────

  defp sqld_execute(sql, args \\ []) do
    body = Jason.encode!(%{
      requests: [
        %{type: "execute", stmt: %{sql: sql, args: Enum.map(args, &sqld_encode_arg/1)}},
        %{type: "close"}
      ]
    })

    case Req.post("#{@sqld_url}/v3/pipeline",
      body: body,
      headers: [{"content-type", "application/json"}],
      receive_timeout: 10_000
    ) do
      {:ok, %{status: 200, body: resp}} ->
        errors = (resp["results"] || []) |> Enum.filter(&(&1["type"] == "error"))
        if errors == [] do
          :ok
        else
          Logger.error("[sqld] Execute error: #{inspect(errors)}")
          {:error, errors}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("[sqld] HTTP #{status}: #{inspect(body)}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.error("[sqld] Request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp sqld_query(sql, args \\ []) do
    body = Jason.encode!(%{
      requests: [
        %{type: "execute", stmt: %{sql: sql, args: Enum.map(args, &sqld_encode_arg/1)}},
        %{type: "close"}
      ]
    })

    case Req.post("#{@sqld_url}/v3/pipeline",
      body: body,
      headers: [{"content-type", "application/json"}],
      receive_timeout: 10_000
    ) do
      {:ok, %{status: 200, body: resp}} ->
        result = resp["results"] |> List.first()

        case result do
          %{"type" => "error", "error" => err} ->
            {:error, err}

          %{"type" => "ok", "response" => %{"result" => %{"rows" => rows}}} ->
            {:ok, Enum.map(rows, &decode_sqld_row/1)}

          _ ->
            {:ok, []}
        end

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sqld_encode_arg(nil),              do: %{"type" => "null", "value" => nil}
  defp sqld_encode_arg(v) when is_integer(v), do: %{"type" => "integer", "value" => to_string(v)}
  defp sqld_encode_arg(v) when is_float(v),   do: %{"type" => "float",   "value" => v}
  defp sqld_encode_arg(v) when is_binary(v),  do: %{"type" => "text",    "value" => v}
  defp sqld_encode_arg(v),                    do: %{"type" => "text",    "value" => to_string(v)}

  defp decode_sqld_row(row) when is_list(row) do
    Enum.map(row, fn
      %{"type" => "null"}    -> nil
      %{"value" => v}        -> v
      v                      -> v
    end)
  end

  defp decode_metadata(nil), do: %{}
  defp decode_metadata(str) when is_binary(str) do
    case Jason.decode(str) do
      {:ok, map} -> map
      _          -> %{}
    end
  end
  defp decode_metadata(map) when is_map(map), do: map

  defp parse_sqld_timestamp(nil), do: DateTime.utc_now()
  defp parse_sqld_timestamp(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _            -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(nil), do: DateTime.add(DateTime.utc_now(), -30, :day)
  defp parse_timestamp(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _            -> DateTime.add(DateTime.utc_now(), -30, :day)
    end
  end
end

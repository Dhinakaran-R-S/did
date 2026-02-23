defmodule AlemWeb.LocalFirstController do
  @moduledoc """
  Controller for local-first operations
  Handles sync, offline queue management, and local data operations
  """

  use AlemWeb, :controller
  require Logger

  alias Alem.LocalFirst.{SyncManager, OfflineQueue}
  alias Alem.Schemas.{LocalUser, LocalDocument}
  alias Alem.LocalFirst.LibSQLRepo

  # Plug for authentication (reuse existing)
  plug AlemWeb.Plugs.PleromaAuth when action in [:sync_to_server, :sync_from_server, :get_sync_status]

  @doc """
  Initialize local user data
  POST /api/v1/local/init
  """
  def init_local_user(conn, params) do
    user_data = %{
      id: params["user_id"] || UUID.uuid4(),
      tenant_id: params["tenant_id"] || "default",
      username: params["username"],
      display_name: params["display_name"],
      email: params["email"],
      oauth_token: params["oauth_token"],
      pleroma_account_id: params["pleroma_account_id"],
      did: params["did"],
      settings: params["settings"] || %{}
    }

    case create_or_update_local_user(user_data) do
      {:ok, user} ->
        # Start sync manager for this user
        start_sync_manager(user.id, user.tenant_id)

        conn
        |> put_status(:created)
        |> json(%{
          message: "Local user initialized",
          user: format_local_user(user)
        })

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Failed to initialize local user",
          details: format_changeset_errors(changeset)
        })
    end
  end

  @doc """
  Add document to local storage
  POST /api/v1/local/documents
  """
  def add_local_document(conn, params) do
    document_data = %{
      id: params["id"] || UUID.uuid4(),
      user_id: params["user_id"],
      tenant_id: params["tenant_id"] || "default",
      filename: params["filename"],
      content_type: params["content_type"],
      file_size: params["file_size"],
      content_hash: params["content_hash"],
      local_path: params["local_path"],
      text_content: params["text_content"],
      metadata: params["metadata"] || %{},
      tags: params["tags"] || []
    }

    case create_local_document(document_data) do
      {:ok, document} ->
        # Queue for sync if user is online
        queue_document_sync(document)

        conn
        |> put_status(:created)
        |> json(%{
          message: "Document added to local storage",
          document: format_local_document(document)
        })

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "Failed to add document",
          details: format_changeset_errors(changeset)
        })
    end
  end

  @doc """
  Get local documents for a user
  GET /api/v1/local/documents
  """
  def list_local_documents(conn, params) do
    user_id = params["user_id"]
    limit = String.to_integer(params["limit"] || "50")
    offset = String.to_integer(params["offset"] || "0")

    case get_local_documents(user_id, limit, offset) do
      {:ok, documents} ->
        conn
        |> json(%{
          documents: Enum.map(documents, &format_local_document/1),
          pagination: %{
            limit: limit,
            offset: offset,
            total: count_local_documents(user_id)
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to list documents", details: inspect(reason)})
    end
  end

  @doc """
  Sync local data to server
  POST /api/v1/local/sync/to-server
  """
  def sync_to_server(conn, _params) do
    user_id = conn.assigns.pleroma_account_id

    case SyncManager.sync_to_server(user_id) do
      :ok ->
        conn
        |> json(%{message: "Sync to server completed successfully"})

      {:error, reason} ->
        Logger.error("[LocalFirstController] Sync to server failed: #{inspect(reason)}")
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Sync failed", details: inspect(reason)})
    end
  end

  @doc """
  Sync server data to local
  POST /api/v1/local/sync/from-server
  """
  def sync_from_server(conn, _params) do
    user_id = conn.assigns.pleroma_account_id

    case SyncManager.sync_from_server(user_id) do
      :ok ->
        conn
        |> json(%{message: "Sync from server completed successfully"})

      {:error, reason} ->
        Logger.error("[LocalFirstController] Sync from server failed: #{inspect(reason)}")
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Sync failed", details: inspect(reason)})
    end
  end

  @doc """
  Get sync status for a user
  GET /api/v1/local/sync/status
  """
  def get_sync_status(conn, _params) do
    user_id = conn.assigns.pleroma_account_id

    case SyncManager.get_sync_status(user_id) do
      status when is_map(status) ->
        # Get offline queue stats
        {:ok, queue_stats} = OfflineQueue.get_queue_stats(user_id)

        conn
        |> json(%{
          sync_status: status,
          offline_queue: queue_stats
        })

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to get sync status", details: inspect(reason)})
    end
  end

  @doc """
  Get offline queue operations
  GET /api/v1/local/offline-queue
  """
  def get_offline_queue(conn, params) do
    user_id = params["user_id"]

    with {:ok, pending} <- OfflineQueue.get_pending_operations(user_id),
         {:ok, failed} <- OfflineQueue.get_retry_operations(user_id),
         {:ok, stats} <- OfflineQueue.get_queue_stats(user_id) do

      conn
      |> json(%{
        pending_operations: Enum.map(pending, &format_operation/1),
        failed_operations: Enum.map(failed, &format_operation/1),
        statistics: stats
      })
    else
      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to get offline queue", details: inspect(reason)})
    end
  end

  @doc """
  Retry failed operations
  POST /api/v1/local/offline-queue/retry
  """
  def retry_failed_operations(conn, params) do
    user_id = params["user_id"]
    operation_ids = params["operation_ids"] || []

    results = Enum.map(operation_ids, fn operation_id ->
      case OfflineQueue.reset_operation_for_retry(operation_id) do
        :ok -> %{operation_id: operation_id, status: "reset"}
        {:error, reason} -> %{operation_id: operation_id, status: "error", reason: inspect(reason)}
      end
    end)

    # Trigger sync attempt
    spawn(fn -> SyncManager.sync_to_server(user_id) end)

    conn
    |> json(%{
      message: "Retry operations queued",
      results: results
    })
  end

  @doc """
  Health check for local-first functionality
  GET /api/v1/local/health
  """
  def health_check(conn, _params) do
    # Check LibSQL connection
    libsql_status = case LibSQLRepo.query("SELECT 1", []) do
      {:ok, _} -> "healthy"
      _ -> "unhealthy"
    end

    conn
    |> json(%{
      status: "ok",
      timestamp: DateTime.utc_now(),
      services: %{
        libsql: libsql_status,
        sync_manager: "running"
      }
    })
  end

  # Private Functions

  defp create_or_update_local_user(user_data) do
    case LibSQLRepo.get(LocalUser, user_data.id) do
      nil ->
        %LocalUser{}
        |> LocalUser.changeset(user_data)
        |> LibSQLRepo.insert()

      existing_user ->
        existing_user
        |> LocalUser.changeset(user_data)
        |> LibSQLRepo.update()
    end
  end

  defp create_local_document(document_data) do
    %LocalDocument{}
    |> LocalDocument.changeset(document_data)
    |> LibSQLRepo.insert()
  end

  defp get_local_documents(user_id, limit, offset) do
    import Ecto.Query

    query = from d in LocalDocument,
      where: d.user_id == ^user_id and d.status != "deleted",
      order_by: [desc: d.inserted_at],
      limit: ^limit,
      offset: ^offset

    try do
      documents = LibSQLRepo.all(query)
      {:ok, documents}
    rescue
      error -> {:error, error}
    end
  end

  defp count_local_documents(user_id) do
    import Ecto.Query

    query = from d in LocalDocument,
      where: d.user_id == ^user_id and d.status != "deleted",
      select: count()

    LibSQLRepo.one(query) || 0
  end

  defp queue_document_sync(document) do
    operation = %{
      type: :create_document,
      data: %{
        id: document.id,
        filename: document.filename,
        content_type: document.content_type,
        local_path: document.local_path,
        metadata: document.metadata
      }
    }

    OfflineQueue.add_operation(document.user_id, operation)
  end

  defp start_sync_manager(user_id, tenant_id) do
    case SyncManager.start_link(user_id: user_id, tenant_id: tenant_id) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error ->
        Logger.error("[LocalFirstController] Failed to start sync manager: #{inspect(error)}")
        error
    end
  end

  defp format_local_user(user) do
    %{
      id: user.id,
      tenant_id: user.tenant_id,
      username: user.username,
      display_name: user.display_name,
      email: user.email,
      pleroma_account_id: user.pleroma_account_id,
      did: user.did,
      identity_type: user.identity_type,
      last_sync_at: user.last_sync_at,
      is_online: user.is_online,
      status: user.status,
      oauth_valid: LocalUser.oauth_valid?(user),
      needs_sync: LocalUser.needs_sync?(user)
    }
  end

  defp format_local_document(document) do
    %{
      id: document.id,
      filename: document.filename,
      content_type: document.content_type,
      file_size: document.file_size,
      is_cached_locally: document.is_cached_locally,
      is_synced: document.is_synced,
      status: document.status,
      tags: document.tags,
      metadata: document.metadata,
      needs_sync: LocalDocument.needs_sync?(document),
      has_conflict: LocalDocument.has_conflict?(document),
      available_offline: LocalDocument.is_available_offline?(document),
      created_at: document.inserted_at,
      updated_at: document.updated_at
    }
  end

  defp format_operation(operation) do
    %{
      id: operation.id,
      type: operation.type,
      status: operation.status,
      retry_count: operation.retry_count,
      error_message: operation.error_message,
      created_at: operation.inserted_at,
      last_retry_at: operation.last_retry_at
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end

defmodule Alem.LocalFirst.SyncManager do
  @moduledoc """
  Manages synchronization between local LibSQL and server storage.
  Handles offline queue, conflict resolution, and bidirectional sync.
  """

  use GenServer
  require Logger

  alias Alem.LocalFirst.{OfflineQueue}
  alias Alem.Storage.ObjectStore
  alias Alem.Repo
  alias Alem.Schemas.Namespace

  defstruct [
    :user_id,
    :tenant_id,
    :sync_state,
    :last_sync_timestamp,
    :pending_operations,
    :connection_status
  ]

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    tenant_id = Keyword.get(opts, :tenant_id, "default")
    GenServer.start_link(__MODULE__, {user_id, tenant_id}, name: via_tuple(user_id))
  end

  def sync_to_server(user_id) do
    GenServer.call(via_tuple(user_id), :sync_to_server, 60_000)
  end

  def sync_from_server(user_id) do
    GenServer.call(via_tuple(user_id), :sync_from_server, 60_000)
  end

  def queue_offline_operation(user_id, operation) do
    GenServer.cast(via_tuple(user_id), {:queue_operation, operation})
  end

  def get_sync_status(user_id) do
    GenServer.call(via_tuple(user_id), :get_status)
  end

  # ---------------------------------------------------------------------------
  # GenServer Implementation
  # ---------------------------------------------------------------------------

  @impl true
  def init({user_id, tenant_id}) do
    Logger.info("[SyncManager] Starting for user: #{user_id}")

    state = %__MODULE__{
      user_id: user_id,
      tenant_id: tenant_id,
      sync_state: :idle,
      last_sync_timestamp: nil,
      pending_operations: [],
      connection_status: :offline
    }

    send(self(), :check_connection)
    schedule_sync_check()
    {:ok, state}
  end

  @impl true
  def handle_call(:sync_to_server, _from, state) do
    case do_sync_to_server(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} = err ->
        Logger.error("[SyncManager] sync_to_server failed: #{inspect(reason)}")
        {:reply, err, state}
    end
  end

  @impl true
  def handle_call(:sync_from_server, _from, state) do
    case do_sync_from_server(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason} = err ->
        Logger.error("[SyncManager] sync_from_server failed: #{inspect(reason)}")
        {:reply, err, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      user_id: state.user_id,
      sync_state: state.sync_state,
      last_sync: state.last_sync_timestamp,
      pending_operations: length(state.pending_operations),
      connection_status: state.connection_status
    }
    {:reply, status, state}
  end

  @impl true
  def handle_cast({:queue_operation, operation}, state) do
    Logger.info("[SyncManager] Queuing offline operation: #{inspect(operation.type)}")
    OfflineQueue.add_operation(state.user_id, operation)

    new_state = %{state | pending_operations: [operation | state.pending_operations]}

    if state.connection_status == :online do
      send(self(), :attempt_sync)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_connection, state) do
    connection_status = check_server_connection()
    new_state = %{state | connection_status: connection_status}

    if connection_status == :online and state.sync_state == :idle do
      send(self(), :attempt_sync)
    end

    Process.send_after(self(), :check_connection, 30_000)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:attempt_sync, state) do
    if state.connection_status == :online and length(state.pending_operations) > 0 do
      case do_sync_to_server(state) do
        {:ok, new_state} -> {:noreply, new_state}
        {:error, _} -> {:noreply, %{state | connection_status: :offline}}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:sync_check, state) do
    if state.connection_status == :online do
      send(self(), :attempt_sync)
    end
    schedule_sync_check()
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Private — high-level sync flows
  # ---------------------------------------------------------------------------

  defp do_sync_to_server(state) do
    Logger.info("[SyncManager] Starting sync to server for user: #{state.user_id}")

    with {:ok, operations} <- OfflineQueue.get_pending_operations(state.user_id),
         {:ok, _results} <- process_operations_to_server(operations, state),
         :ok <- OfflineQueue.clear_processed_operations(state.user_id) do

      new_state = %{state |
        sync_state: :idle,
        last_sync_timestamp: DateTime.utc_now(),
        pending_operations: []
      }
      Logger.info("[SyncManager] Sync to server completed")
      {:ok, new_state}
    else
      error ->
        Logger.error("[SyncManager] Sync to server failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp do_sync_from_server(state) do
    Logger.info("[SyncManager] Starting sync from server for user: #{state.user_id}")
    last_sync = state.last_sync_timestamp || DateTime.add(DateTime.utc_now(), -30, :day)

    with {:ok, server_changes} <- fetch_server_changes(state.user_id, last_sync),
         :ok <- apply_server_changes_locally(server_changes, state) do

      new_state = %{state | sync_state: :idle, last_sync_timestamp: DateTime.utc_now()}
      Logger.info("[SyncManager] Sync from server completed")
      {:ok, new_state}
    else
      error ->
        Logger.error("[SyncManager] Sync from server failed: #{inspect(error)}")
        {:error, error}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — operation dispatch
  # ---------------------------------------------------------------------------

  defp process_operations_to_server(operations, state) do
    Enum.reduce_while(operations, {:ok, []}, fn operation, {:ok, results} ->
      case process_single_operation(operation, state) do
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        {:error, reason} = err ->
          Logger.error("[SyncManager] Failed to process op #{operation.id}: #{inspect(reason)}")
          {:halt, err}
      end
    end)
  end

  defp process_single_operation(operation, state) do
    case operation.type do
      :create_document -> sync_document_to_server(operation.data, state)
      :update_document -> update_document_on_server(operation.data, state)
      :delete_document -> delete_document_on_server(operation.data, state)
      :create_did      -> sync_did_to_server(operation.data, state)
      :update_profile  -> sync_profile_to_server(operation.data, state)
      _ ->
        Logger.warning("[SyncManager] Unknown operation type: #{operation.type}")
        {:ok, :skipped}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — document operations
  # ---------------------------------------------------------------------------

  defp sync_document_to_server(document_data, state) do
    with {:ok, object_key} <- upload_file_to_storage(document_data, state),
         {:ok, _meta} <- create_document_metadata_on_server(document_data, object_key, state) do
      {:ok, :synced}
    end
  end

  defp update_document_on_server(document_data, state) do
    url = "#{get_server_base_url()}/api/v1/sync/apply"

    payload = %{
      changes: [
        %{
          type: "update_document",
          id: document_data.id,
          data: Map.merge(document_data, %{user_id: state.user_id, tenant_id: state.tenant_id})
        }
      ]
    }

    case Req.post(url, json: payload, headers: auth_headers(state.user_id)) do
      {:ok, %{status: status}} when status in [200, 201] ->
        Logger.info("[SyncManager] Document #{document_data.id} updated on server")
        {:ok, :updated}
      {:ok, %{status: status, body: body}} ->
        Logger.error("[SyncManager] Update document failed #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        Logger.error("[SyncManager] Update document request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp delete_document_on_server(document_data, state) do
    url = "#{get_server_base_url()}/api/v1/sync/apply"

    payload = %{
      changes: [
        %{
          type: "delete_document",
          id: document_data[:id] || document_data["id"],
          data: %{
            id: document_data[:id] || document_data["id"],
            user_id: state.user_id,
            tenant_id: state.tenant_id
          }
        }
      ]
    }

    case Req.post(url, json: payload, headers: auth_headers(state.user_id)) do
      {:ok, %{status: status}} when status in [200, 204] ->
        Logger.info("[SyncManager] Document #{document_data[:id]} deleted on server")
        {:ok, :deleted}
      {:ok, %{status: status, body: body}} ->
        Logger.error("[SyncManager] Delete document failed #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        Logger.error("[SyncManager] Delete document request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — DID operations
  # ---------------------------------------------------------------------------

  defp sync_did_to_server(did_data, state) do
    url = "#{get_server_base_url()}/api/v1/namespaces"
    token = get_user_oauth_token_value(state.user_id)

    payload = %{
      did: did_data[:did] || did_data["did"],
      identity_type: did_data[:identity_type] || did_data["identity_type"] || "did"
    }

    headers = if token, do: [{"Authorization", "Bearer #{token}"}], else: []

    case Req.post(url, json: payload, headers: headers) do
      {:ok, %{status: status}} when status in [200, 201] ->
        Logger.info("[SyncManager] DID synced to server for user #{state.user_id}")
        {:ok, :synced}
      {:ok, %{status: status, body: body}} ->
        Logger.error("[SyncManager] DID sync failed #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        Logger.error("[SyncManager] DID sync request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — profile operations
  # ---------------------------------------------------------------------------

  defp sync_profile_to_server(profile_data, state) do
    url = "#{get_server_base_url()}/api/v1/namespaces"
    token = get_user_oauth_token_value(state.user_id)

    payload = %{
      config: %{
        profile: profile_data
      }
    }

    headers = if token, do: [{"Authorization", "Bearer #{token}"}], else: []

    case Req.post(url, json: payload, headers: headers) do
      {:ok, %{status: status}} when status in [200, 201] ->
        Logger.info("[SyncManager] Profile synced for user #{state.user_id}")
        {:ok, :synced}
      {:ok, %{status: status, body: body}} ->
        Logger.error("[SyncManager] Profile sync failed #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        Logger.error("[SyncManager] Profile sync request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — file upload helpers
  # ---------------------------------------------------------------------------

  defp upload_file_to_storage(document_data, state) do
    bucket = Application.get_env(:alem, :file_storage)[:bucket]
    key = "tenant/#{state.tenant_id}/#{state.user_id}/documents/#{document_data.id}/#{document_data.filename}"

    case get_local_file_content(document_data.local_path) do
      {:ok, content} ->
        case ObjectStore.put(bucket, key, content, %{
          content_type: document_data[:content_type] || "application/octet-stream",
          metadata: %{"tenant_id" => state.tenant_id, "user_id" => state.user_id}
        }) do
          :ok -> {:ok, key}
          error -> error
        end
      error ->
        error
    end
  end

  defp create_document_metadata_on_server(document_data, object_key, state) do
    url = "#{get_server_base_url()}/api/v1/sync/apply"

    payload = %{
      changes: [
        %{
          type: "create_document",
          id: document_data.id,
          data: %{
            id: document_data.id,
            user_id: state.user_id,
            tenant_id: state.tenant_id,
            filename: document_data.filename,
            content_type: document_data[:content_type],
            object_key: object_key,
            content_hash: document_data[:content_hash],
            text_content: document_data[:text_content],
            metadata: document_data[:metadata] || %{}
          }
        }
      ]
    }

    case Req.post(url, json: payload, headers: auth_headers(state.user_id)) do
      {:ok, %{status: status}} when status in [200, 201] ->
        {:ok, :created}
      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — server sync helpers
  # ---------------------------------------------------------------------------

  defp fetch_server_changes(user_id, since_timestamp) do
    url = "#{get_server_base_url()}/api/v1/sync/changes"

    params = %{
      since: DateTime.to_iso8601(since_timestamp),
      user_id: user_id
    }

    case Req.get(url, params: params, headers: auth_headers(user_id)) do
      {:ok, %{status: 200, body: changes}} -> {:ok, changes}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_server_changes_locally(changes, _state) when is_list(changes) do
    Enum.reduce_while(changes, :ok, fn change, :ok ->
      case apply_change_locally(change) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp apply_server_changes_locally(_changes, _state), do: :ok

  defp apply_change_locally(change) do
    case change["type"] do
      "document_created" -> insert_document_metadata_locally(change["data"])
      "document_updated" -> update_document_metadata_locally(change["data"])
      "document_deleted" -> delete_document_metadata_locally(change["data"])
      type ->
        Logger.warning("[SyncManager] Unknown change type: #{type}")
        :ok
    end
  end

  defp insert_document_metadata_locally(_document_data) do
    # TODO: write to local LibSQL via libsql WASM bindings or Ecto SQLite repo
    # Placeholder — implement when local DB adapter is wired in
    :ok
  end

  defp update_document_metadata_locally(_document_data) do
    # TODO: update record in local LibSQL
    :ok
  end

  defp delete_document_metadata_locally(_document_data) do
    # TODO: soft-delete record in local LibSQL
    :ok
  end

  # ---------------------------------------------------------------------------
  # Private — local file access
  # ---------------------------------------------------------------------------

  defp get_local_file_content(local_path) when is_binary(local_path) do
    case File.read(local_path) do
      {:ok, _content} = ok -> ok
      {:error, reason} ->
        Logger.error("[SyncManager] Failed to read local file #{local_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_local_file_content(nil), do: {:error, :no_local_path}

  # ---------------------------------------------------------------------------
  # Private — network / auth helpers
  # ---------------------------------------------------------------------------

  defp check_server_connection do
    url = "#{get_server_base_url()}/api/v1/health"

    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200}} -> :online
      _ -> :offline
    end
  end

  defp get_server_base_url do
    Application.get_env(:alem, :server_base_url, "http://localhost:4000")
  end

  defp auth_headers(user_id) do
    case get_user_oauth_token_value(user_id) do
      nil -> []
      token -> [{"Authorization", "Bearer #{token}"}]
    end
  end

  # Renamed from get_user_oauth_token to avoid unused-variable warning on the
  # parameter when the function body is a stub.
  defp get_user_oauth_token_value(_user_id) do
    # TODO: read from local LibSQL local_users table
    # e.g. LibSQLRepo.get_oauth_token(user_id)
    nil
  end

  defp via_tuple(user_id) do
    {:via, Registry, {Alem.LocalFirst.SyncRegistry, user_id}}
  end

  defp schedule_sync_check do
    Process.send_after(self(), :sync_check, 300_000)
  end
end

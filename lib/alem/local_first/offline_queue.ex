defmodule Alem.LocalFirst.OfflineQueue do
  @moduledoc """
  Manages offline operations queue in LibSQL.
  Stores operations that need to be synced when connection is restored.
  """

  import Ecto.Query
  require Logger

  alias Alem.LocalFirst.LibSQLRepo
  alias Alem.Schemas.OfflineOperation

  @doc """
  Add an operation to the offline queue.
  """
  def add_operation(user_id, operation) do
    attrs = %{
      id: UUID.uuid4(),
      user_id: user_id,
      type: to_string(operation.type),
      data: operation.data,
      status: "pending",
      retry_count: 0
    }
    # NOTE: inserted_at and updated_at are managed automatically by Ecto timestamps().
    # Do NOT set created_at — the schema uses timestamps() which gives inserted_at/updated_at.

    case %OfflineOperation{} |> OfflineOperation.changeset(attrs) |> LibSQLRepo.insert() do
      {:ok, _record} ->
        Logger.info("[OfflineQueue] Added operation #{operation.type} for user #{user_id}")
        :ok

      {:error, reason} ->
        Logger.error("[OfflineQueue] Failed to add operation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Get all pending operations for a user, ordered oldest-first.
  """
  def get_pending_operations(user_id) do
    query =
      from o in OfflineOperation,
        where: o.user_id == ^user_id and o.status == "pending",
        order_by: [asc: o.inserted_at]

    try do
      {:ok, LibSQLRepo.all(query)}
    rescue
      error ->
        Logger.error("[OfflineQueue] Failed to get pending operations: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Mark a list of operations as processed.
  """
  def mark_operations_processed(operation_ids) when is_list(operation_ids) do
    query = from o in OfflineOperation, where: o.id in ^operation_ids

    case LibSQLRepo.update_all(query,
           set: [status: "processed", processed_at: DateTime.utc_now()]
         ) do
      {count, _} when count > 0 ->
        Logger.info("[OfflineQueue] Marked #{count} operations as processed")
        :ok

      {0, _} ->
        Logger.warning("[OfflineQueue] No operations found to mark as processed")
        :ok

      error ->
        Logger.error("[OfflineQueue] Failed to mark processed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Mark a single operation as failed and increment its retry count.
  """
  def mark_operation_failed(operation_id, error_message) do
    query = from o in OfflineOperation, where: o.id == ^operation_id

    case LibSQLRepo.update_all(query,
           inc: [retry_count: 1],
           set: [
             status: "failed",
             error_message: error_message,
             last_retry_at: DateTime.utc_now()
           ]
         ) do
      {1, _} ->
        Logger.warning("[OfflineQueue] Marked #{operation_id} as failed: #{error_message}")
        :ok

      {0, _} ->
        Logger.error("[OfflineQueue] Operation #{operation_id} not found")
        {:error, :not_found}

      error ->
        Logger.error("[OfflineQueue] Failed to mark as failed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Delete all processed operations for a user (cleanup).
  """
  def clear_processed_operations(user_id) do
    query =
      from o in OfflineOperation,
        where: o.user_id == ^user_id and o.status == "processed"

    case LibSQLRepo.delete_all(query) do
      {count, _} ->
        Logger.info("[OfflineQueue] Cleared #{count} processed operations for user #{user_id}")
        :ok

      error ->
        Logger.error("[OfflineQueue] Failed to clear processed: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Get failed operations eligible for retry (retry_count < max_retries).
  """
  def get_retry_operations(user_id, max_retries \\ 3) do
    query =
      from o in OfflineOperation,
        where:
          o.user_id == ^user_id and
            o.status == "failed" and
            o.retry_count < ^max_retries,
        order_by: [asc: o.last_retry_at]

    try do
      {:ok, LibSQLRepo.all(query)}
    rescue
      error ->
        Logger.error("[OfflineQueue] Failed to get retry operations: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Reset a failed operation back to pending so it will be retried.
  """
  def reset_operation_for_retry(operation_id) do
    query = from o in OfflineOperation, where: o.id == ^operation_id

    case LibSQLRepo.update_all(query, set: [status: "pending", error_message: nil]) do
      {1, _} ->
        Logger.info("[OfflineQueue] Reset #{operation_id} for retry")
        :ok

      {0, _} ->
        {:error, :not_found}

      error ->
        {:error, error}
    end
  end

  @doc """
  Return queue statistics for a user.
  """
  def get_queue_stats(user_id) do
    with {:ok, pending} <- safe_count(user_id, "pending"),
         {:ok, failed} <- safe_count(user_id, "failed"),
         {:ok, processed} <- safe_count(user_id, "processed") do
      {:ok,
       %{
         pending: pending,
         failed: failed,
         processed: processed,
         total: pending + failed + processed
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp safe_count(user_id, status) do
    query =
      from o in OfflineOperation,
        where: o.user_id == ^user_id and o.status == ^status,
        select: count()

    try do
      {:ok, LibSQLRepo.one(query) || 0}
    rescue
      error ->
        Logger.error("[OfflineQueue] Count failed for #{status}: #{inspect(error)}")
        {:error, error}
    end
  end
end

defmodule Alem.Namespace.PleromaIntegration do
  @moduledoc """
  Pleroma Integration for Namespaces

  Provides integration between Pleroma accounts and namespaces:
  - Associates Pleroma accounts with namespaces
  - Uses Pleroma OAuth tokens for authentication
  - Syncs namespace data with Pleroma
  - Manages namespace access via Pleroma accounts
  """

  require Logger
  alias Alem.Namespace
  alias Alem.Namespace.Manager
  alias Alem.Identity.DID

  @type pleroma_account_id :: String.t()
  @type namespace_user_id :: String.t()
  @type oauth_token :: String.t()

  @doc """
  Create or get a namespace for a Pleroma account
  """
  def ensure_namespace_for_pleroma_account(pleroma_account_id, oauth_token, opts \\ []) do
    tenant_id = opts[:tenant_id] || "default"

    # Verify the OAuth token with Pleroma
    case verify_pleroma_token(oauth_token) do
      {:ok, account_info} ->
        # Check if namespace already exists for this Pleroma account
        existing_namespace = Manager.find_by_pleroma_account(pleroma_account_id)

        # Generate or use existing DID
        {did, did_keypair} = case existing_namespace do
          nil ->
            # New namespace - generate DID
            case DID.generate(opts[:did_method] || :key, opts[:did_opts] || []) do
              {:ok, new_did, keypair} -> {new_did, keypair}
              {:ok, new_did} -> {new_did, nil}
              error ->
                Logger.warning("Failed to generate DID: #{inspect(error)}, using Pleroma ID")
                {nil, nil}
            end
          namespace ->
            # Use existing DID if available
            {namespace.did, nil}
        end

        # Determine user_id: prefer DID if available, fallback to Pleroma account ID
        user_id = did || pleroma_account_id

        # Prepare Pleroma config
        pleroma_data = %{
          pleroma_account_id: pleroma_account_id,
          pleroma_account_info: account_info,
          oauth_token: oauth_token,
          synced_at: DateTime.utc_now()
        }

        # Build config with DID and Pleroma data
        config_data = %{
          pleroma: pleroma_data
        }
        config_data = if did, do: Map.put(config_data, :did, did), else: config_data
        config_data = if did_keypair, do: Map.put(config_data, :did_keypair, encode_keypair_for_json(did_keypair)), else: config_data

        # Add config to opts
        merged_opts = Keyword.put(opts, :config, config_data)

        # Start or get existing namespace (will persist to DB automatically)
        case Namespace.ensure_started(user_id, tenant_id, merged_opts) do
          {:ok, _pid} ->
            # Config is already persisted via Manager.start, but update to ensure latest
            update_pleroma_config(user_id, pleroma_data)
            {:ok, user_id, account_info}

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Get namespace for a Pleroma account
  """
  def get_namespace_for_pleroma_account(pleroma_account_id, oauth_token) do
    user_id = pleroma_account_id

    # Verify token and check if namespace exists
    case verify_pleroma_token(oauth_token) do
      {:ok, account_info} ->
        if Namespace.exists?(user_id) do
          {:ok, user_id, account_info}
        else
          {:error, :namespace_not_found}
        end

      error ->
        error
    end
  end

  @doc """
  Sync namespace data with Pleroma account
  """
  def sync_namespace_with_pleroma(user_id, oauth_token, opts \\ []) do
    case verify_pleroma_token(oauth_token) do
      {:ok, account_info} ->
        # Get namespace documents
        case Namespace.list_documents(user_id) do
          {:ok, documents} ->
            # Sync documents to Pleroma (e.g., as posts, bookmarks, etc.)
            sync_documents_to_pleroma(user_id, documents, account_info, oauth_token, opts)

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Get Pleroma account info for a namespace
  """
  def get_pleroma_account_info(user_id) do
    case Manager.get_config(user_id) do
      {:ok, config} ->
        account_info = get_in(config, [:pleroma, :pleroma_account_info])
        if account_info do
          {:ok, account_info}
        else
          {:error, :no_pleroma_account}
        end

      error ->
        error
    end
  end

  @doc """
  Update Pleroma OAuth token for a namespace
  """
  def update_pleroma_token(user_id, new_token) do
    case verify_pleroma_token(new_token) do
      {:ok, account_info} ->
        update_pleroma_config(user_id, %{
          oauth_token: new_token,
          pleroma_account_info: account_info,
          synced_at: DateTime.utc_now()
        })
        {:ok, account_info}

      error ->
        error
    end
  end

  # Private Functions

  defp verify_pleroma_token(token) do
    pleroma_base_url = get_pleroma_base_url()
    url = "#{pleroma_base_url}/api/v1/accounts/verify_credentials"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: account_info}} ->
        # Ensure account_info is a map, not a string
        parsed_info = parse_response_body(account_info)
        account_id = parsed_info["id"] || parsed_info[:id] || "unknown"
        Logger.info("Pleroma token verified for account: #{account_id}")
        {:ok, parsed_info}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Pleroma token verification failed: #{status} - #{inspect(body)}")
        {:error, :invalid_token}

      {:error, reason} ->
        Logger.error("Failed to verify Pleroma token: #{inspect(reason)}")
        {:error, :connection_failed}
    end
  end

  defp update_pleroma_config(user_id, pleroma_data) do
    case Manager.get_config(user_id) do
      {:ok, config} ->
        updated_config = put_in(config, [:pleroma], pleroma_data)
        Manager.update_config(user_id, updated_config)
        :ok

      error ->
        error
    end
  end

  defp sync_documents_to_pleroma(user_id, documents, _account_info, _oauth_token, opts) do
    Logger.info("Syncing #{length(documents)} documents to Pleroma for user #{user_id}")

    # For now, just log the sync
    # In a full implementation, you would:
    # 1. Convert documents to Pleroma posts/bookmarks
    # 2. Upload to Pleroma via API
    # 3. Track sync status

    sync_mode = opts[:sync_mode] || :metadata_only

    case sync_mode do
      :metadata_only ->
        # Just sync document metadata
        Logger.info("Metadata-only sync completed for #{length(documents)} documents")
        {:ok, %{synced_count: length(documents), mode: :metadata_only}}

      :full ->
        # Full sync - upload documents as posts
        Logger.info("Full sync mode - would upload documents as Pleroma posts")
        {:ok, %{synced_count: length(documents), mode: :full}}

      _ ->
        {:error, :invalid_sync_mode}
    end
  end

  defp get_pleroma_base_url do
    Application.get_env(:alem, :pleroma, [])[:base_url] ||
      System.get_env("PLEROMA_BASE_URL") ||
      "http://localhost:4001"
  end

  # Helper to parse response body - handles both string and map responses
  defp parse_response_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> body
    end
  end

  defp parse_response_body(body) when is_map(body), do: body
  defp parse_response_body(body), do: body

  # Helper to encode keypair binary keys to base64 for JSON storage
  defp encode_keypair_for_json(keypair) when is_map(keypair) do
    keypair
    |> Enum.map(fn
      {key, value} when is_binary(value) ->
        # Encode binary data to base64
        {key, Base.encode64(value)}
      {key, value} ->
        {key, value}
    end)
    |> Enum.into(%{})
  end

  defp encode_keypair_for_json(keypair), do: keypair
end

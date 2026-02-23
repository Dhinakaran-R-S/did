defmodule Alem.Schemas.LocalDocument do
  @moduledoc """
  Schema for local document metadata stored in LibSQL
  Contains document information for offline access
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime]

  schema "local_documents" do
    field :user_id, :string
    field :tenant_id, :string
    field :filename, :string
    field :content_type, :string
    field :file_size, :integer
    field :content_hash, :string

    # Local storage information
    field :local_path, :string      # Path in IndexedDB/OPFS for WASM
    field :is_cached_locally, :boolean, default: false
    field :local_version, :integer, default: 1

    # Server storage information
    field :object_key, :string      # S3 object key
    field :server_version, :integer, default: 1
    field :is_synced, :boolean, default: false
    field :last_synced_at, :utc_datetime

    # Content and metadata
    field :text_content, :string    # Extracted text for search
    field :metadata, :map, default: %{}
    field :tags, {:array, :string}, default: []

    # Status and sync
    field :status, :string, default: "local"  # local, syncing, synced, conflict
    field :sync_error, :string
    field :needs_upload, :boolean, default: true
    field :needs_download, :boolean, default: false

    timestamps()
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :id, :user_id, :tenant_id, :filename, :content_type, :file_size, :content_hash,
      :local_path, :is_cached_locally, :local_version,
      :object_key, :server_version, :is_synced, :last_synced_at,
      :text_content, :metadata, :tags,
      :status, :sync_error, :needs_upload, :needs_download
    ])
    |> validate_required([:id, :user_id, :tenant_id, :filename])
    |> validate_inclusion(:status, ["local", "syncing", "synced", "conflict", "deleted"])
    |> validate_number(:file_size, greater_than_or_equal_to: 0)
    |> validate_number(:local_version, greater_than: 0)
    |> validate_number(:server_version, greater_than: 0)
  end

  def needs_sync?(%__MODULE__{is_synced: false}), do: true
  def needs_sync?(%__MODULE__{local_version: local_v, server_version: server_v})
    when local_v != server_v, do: true
  def needs_sync?(%__MODULE__{needs_upload: true}), do: true
  def needs_sync?(%__MODULE__{needs_download: true}), do: true
  def needs_sync?(_), do: false

  def has_conflict?(%__MODULE__{status: "conflict"}), do: true
  def has_conflict?(_), do: false

  def is_available_offline?(%__MODULE__{is_cached_locally: true}), do: true
  def is_available_offline?(_), do: false
end

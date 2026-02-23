defmodule Alem.Repo.Migrations.CreateLocalDocuments do
  use Ecto.Migration

  def change do
    create table(:local_documents, primary_key: false) do
      add :id, :string, primary_key: true
      add :user_id, :string, null: false
      add :tenant_id, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string
      add :file_size, :bigint
      add :content_hash, :string

      # Local storage information
      add :local_path, :string
      add :is_cached_locally, :boolean, default: false
      add :local_version, :integer, default: 1

      # Server storage information
      add :object_key, :string
      add :server_version, :integer, default: 1
      add :is_synced, :boolean, default: false
      add :last_synced_at, :utc_datetime

      # Content and metadata
      add :text_content, :text
      add :metadata, :map, default: %{}
      add :tags, {:array, :string}, default: []

      # Status and sync
      add :status, :string, default: "local"
      add :sync_error, :string
      add :needs_upload, :boolean, default: true
      add :needs_download, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:local_documents, [:user_id])
    create index(:local_documents, [:tenant_id])
    create index(:local_documents, [:user_id, :tenant_id])
    create index(:local_documents, [:status])
    create index(:local_documents, [:needs_upload])
    create index(:local_documents, [:needs_download])
    create index(:local_documents, [:is_synced])
    create index(:local_documents, [:content_hash])
    create index(:local_documents, [:tags], using: :gin)

    # Full-text search index for text content
    execute(
      "CREATE INDEX local_documents_text_content_idx ON local_documents USING GIN (to_tsvector('english', text_content))",
      "DROP INDEX local_documents_text_content_idx"
    )
  end
end

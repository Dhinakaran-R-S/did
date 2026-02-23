defmodule Alem.Repo.Migrations.CreateLocalUsers do
  use Ecto.Migration

  def change do
    create table(:local_users, primary_key: false) do
      add :id, :string, primary_key: true
      add :tenant_id, :string, null: false, default: "default"
      add :username, :string
      add :display_name, :string
      add :email, :string
      add :avatar_url, :string

      # OAuth and authentication
      add :oauth_token, :text
      add :oauth_refresh_token, :text
      add :oauth_expires_at, :utc_datetime
      add :pleroma_account_id, :string

      # DID information
      add :did, :string
      add :did_keypair, :map  # Encrypted keypair data
      add :identity_type, :string, default: "hybrid"

      # Sync metadata
      add :last_sync_at, :utc_datetime
      add :sync_token, :string
      add :is_online, :boolean, default: false

      # Local settings
      add :settings, :map, default: %{}
      add :status, :string, default: "active"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:local_users, [:pleroma_account_id], where: "pleroma_account_id IS NOT NULL")
    create unique_index(:local_users, [:did], where: "did IS NOT NULL")
    create index(:local_users, [:tenant_id])
    create index(:local_users, [:status])
    create index(:local_users, [:last_sync_at])
  end
end

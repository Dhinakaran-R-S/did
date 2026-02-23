defmodule Alem.Repo.Migrations.AddDidToNamespaces do
  use Ecto.Migration

  def change do
    alter table(:namespaces) do
      add :did, :string
      add :identity_type, :string, default: "pleroma"
      add :pleroma_account_id, :string
    end

    # Index for DID lookups
    create index(:namespaces, [:did], unique: true, where: "did IS NOT NULL")

    # Index for Pleroma account lookups
    create index(:namespaces, [:pleroma_account_id], unique: true, where: "pleroma_account_id IS NOT NULL")

    # Composite index for identity resolution
    create index(:namespaces, [:identity_type, :did, :pleroma_account_id])
  end
end

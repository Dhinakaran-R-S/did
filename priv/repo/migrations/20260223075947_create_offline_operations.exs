defmodule Alem.Repo.Migrations.CreateOfflineOperations do
  use Ecto.Migration

  def change do
    create table(:offline_operations, primary_key: false) do
      add :id, :string, primary_key: true
      add :user_id, :string, null: false
      add :type, :string, null: false
      add :data, :map, null: false
      add :status, :string, default: "pending", null: false
      add :retry_count, :integer, default: 0, null: false
      add :error_message, :string
      add :last_retry_at, :utc_datetime
      add :processed_at, :utc_datetime

      # Ecto timestamps() generates inserted_at + updated_at, NOT created_at
      timestamps(type: :utc_datetime)
    end

    create index(:offline_operations, [:user_id, :status])
    create index(:offline_operations, [:user_id])
    # Use inserted_at — this is what Ecto timestamps() actually creates
    create index(:offline_operations, [:inserted_at])
  end
end

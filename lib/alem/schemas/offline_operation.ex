defmodule Alem.Schemas.OfflineOperation do
  @moduledoc """
  Schema for offline operations queue
  Stores operations that need to be synced when connection is restored
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime]

  schema "offline_operations" do
    field :user_id, :string
    field :type, :string  # create_document, update_document, delete_document, etc.
    field :data, :map     # Operation-specific data
    field :status, :string, default: "pending"  # pending, processed, failed
    field :retry_count, :integer, default: 0
    field :error_message, :string
    field :last_retry_at, :utc_datetime
    field :processed_at, :utc_datetime

    timestamps()
  end

  def changeset(operation, attrs) do
    operation
    |> cast(attrs, [:id, :user_id, :type, :data, :status, :retry_count, :error_message, :last_retry_at, :processed_at])
    |> validate_required([:id, :user_id, :type, :data])
    |> validate_inclusion(:status, ["pending", "processed", "failed"])
    |> validate_inclusion(:type, [
      "create_document", "update_document", "delete_document",
      "create_did", "update_did",
      "update_profile", "create_namespace"
    ])
  end
end

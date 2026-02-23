defmodule Alem.Schemas.LocalUser do
  @moduledoc """
  Schema for local user data stored in LibSQL
  Contains essential user information for offline operation
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime]

  schema "local_users" do
    field :tenant_id, :string, default: "default"
    field :username, :string
    field :display_name, :string
    field :email, :string
    field :avatar_url, :string

    # OAuth and authentication
    field :oauth_token, :string
    field :oauth_refresh_token, :string
    field :oauth_expires_at, :utc_datetime
    field :pleroma_account_id, :string

    # DID information
    field :did, :string
    field :did_keypair, :map  # Encrypted keypair data
    field :identity_type, :string, default: "hybrid"

    # Sync metadata
    field :last_sync_at, :utc_datetime
    field :sync_token, :string  # For incremental sync
    field :is_online, :boolean, default: false

    # Local settings
    field :settings, :map, default: %{}
    field :status, :string, default: "active"

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :id, :tenant_id, :username, :display_name, :email, :avatar_url,
      :oauth_token, :oauth_refresh_token, :oauth_expires_at, :pleroma_account_id,
      :did, :did_keypair, :identity_type,
      :last_sync_at, :sync_token, :is_online,
      :settings, :status
    ])
    |> validate_required([:id, :tenant_id])
    |> validate_format(:email, ~r/@/, message: "must be a valid email")
    |> validate_inclusion(:status, ["active", "suspended", "deleted"])
    |> validate_inclusion(:identity_type, ["pleroma", "did", "hybrid"])
    |> unique_constraint(:id)
    |> unique_constraint(:pleroma_account_id)
    |> unique_constraint(:did)
  end

  def oauth_valid?(%__MODULE__{oauth_expires_at: nil}), do: false
  def oauth_valid?(%__MODULE__{oauth_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  def needs_sync?(%__MODULE__{last_sync_at: nil}), do: true
  def needs_sync?(%__MODULE__{last_sync_at: last_sync}) do
    # Sync if last sync was more than 1 hour ago
    diff = DateTime.diff(DateTime.utc_now(), last_sync, :second)
    diff > 3600
  end
end

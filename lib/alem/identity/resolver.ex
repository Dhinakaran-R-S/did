defmodule Alem.Identity.Resolver do
  @moduledoc """
  Identity resolution utilities

  Resolves user identities across different identifier types:
  - DID (Decentralized Identifier)
  - Pleroma account ID
  - Namespace ID
  """

  alias Alem.Namespace.Manager
  alias Alem.Identity.DID

  @doc """
  Resolve an identifier to a namespace.

  Supports:
  - DID (did:key:..., did:web:..., etc.)
  - Pleroma account ID
  - Namespace ID
  """
  def resolve_to_namespace(identifier) do
    cond do
      DID.valid?(identifier) ->
        # Resolve DID to namespace
        case Manager.find_by_did(identifier) do
          nil -> {:error, :namespace_not_found}
          namespace -> {:ok, namespace}
        end

      true ->
        # Try as namespace ID or Pleroma account ID
        case Manager.find_namespace(identifier) do
          nil -> {:error, :namespace_not_found}
          namespace -> {:ok, namespace}
        end
    end
  end

  @doc """
  Get the primary identifier for a namespace.

  Returns DID if available, otherwise falls back to namespace ID.
  """
  def primary_identifier(namespace) do
    namespace.did || namespace.id
  end

  @doc """
  Get all identifiers associated with a namespace.
  """
  def all_identifiers(namespace) do
    identifiers = [namespace.id]
    identifiers = if namespace.did, do: [namespace.did | identifiers], else: identifiers
    identifiers = if namespace.pleroma_account_id,
                  do: [namespace.pleroma_account_id | identifiers],
                  else: identifiers
    identifiers
  end

  @doc """
  Check if two identifiers refer to the same namespace.
  """
  def same_identity?(identifier1, identifier2) do
    case {resolve_to_namespace(identifier1), resolve_to_namespace(identifier2)} do
      {{:ok, ns1}, {:ok, ns2}} -> ns1.id == ns2.id
      _ -> false
    end
  end
end

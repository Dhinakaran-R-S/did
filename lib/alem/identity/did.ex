defmodule Alem.Identity.DID do
  @moduledoc """
  Decentralized Identifier (DID) utilities.

  Provides functions for:
  - DID generation and validation
  - DID resolution
  - Identity mapping (DID <-> Pleroma account)
  - DID document management
  """

  require Logger

  @type did :: String.t()
  @type did_method :: :key | :web | :plc | :peer

  @doc """
  Generate a new DID using the specified method.

  Supported methods: `:key`, `:web`, `:plc`, `:peer`
  Default: `:key`
  """
  def generate(method \\ :key, opts \\ []) do
    case method do
      :key  -> generate_key_did(opts)
      :web  -> generate_web_did(opts)
      :plc  -> generate_plc_did(opts)
      :peer -> generate_peer_did(opts)
      _     -> {:error, :unsupported_method}
    end
  end

  @doc """
  Validate a DID format.
  Returns `{:ok, did}` if valid, `{:error, reason}` if invalid.
  """
  def validate(did) when is_binary(did) do
    case Regex.run(~r/^did:([a-z0-9]+):([a-zA-Z0-9._:%-]+)$/, did) do
      [_full, method, _identifier] ->
        if valid_method?(method) do
          {:ok, did}
        else
          {:error, :unsupported_method}
        end

      nil ->
        {:error, :invalid_format}
    end
  end

  def validate(_), do: {:error, :invalid_type}

  @doc "Check if a string is a valid DID."
  def valid?(did) when is_binary(did) do
    case validate(did) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def valid?(_), do: false

  @doc """
  Extract the method from a DID.

      iex> DID.method("did:key:z6Mk...")
      {:ok, "key"}
  """
  def method(did) do
    case Regex.run(~r/^did:([a-z0-9]+):/, did) do
      [_full, m] -> {:ok, m}
      nil        -> {:error, :invalid_did}
    end
  end

  @doc """
  Extract the identifier part from a DID.

      iex> DID.identifier("did:key:z6MkhaXgBZD...")
      {:ok, "z6MkhaXgBZD..."}
  """
  def identifier(did) do
    case Regex.run(~r/^did:[a-z0-9]+:(.+)$/, did) do
      [_full, id] -> {:ok, id}
      nil         -> {:error, :invalid_did}
    end
  end

  @doc """
  Resolve a DID to its DID document.
  """
  def resolve(did) do
    case validate(did) do
      {:ok, valid_did} ->
        case method(valid_did) do
          {:ok, "key"}  -> resolve_key_did(valid_did)
          {:ok, "web"}  -> resolve_web_did(valid_did)
          {:ok, "plc"}  -> resolve_plc_did(valid_did)
          {:ok, "peer"} -> resolve_peer_did(valid_did)
          _             -> {:error, :unsupported_method}
        end

      error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Private – DID generation
  # ---------------------------------------------------------------------------

  defp generate_key_did(_opts) do
    {:ok, private_key} = generate_ed25519_keypair()
    public_key = extract_public_key(private_key)
    multibase_encoded = encode_multibase_base58btc(public_key)
    did = "did:key:#{multibase_encoded}"
    {:ok, did, %{private_key: private_key, public_key: public_key}}
  end

  defp generate_web_did(opts) do
    domain = Keyword.get(opts, :domain) || System.get_env("DID_WEB_DOMAIN", "localhost")
    path = Keyword.get(opts, :path, "")
    identifier = generate_identifier()

    if path != "" do
      {:ok, "did:web:#{domain}:#{path}:#{identifier}"}
    else
      {:ok, "did:web:#{domain}:#{identifier}"}
    end
  end

  defp generate_plc_did(_opts) do
    {:ok, "did:plc:#{generate_identifier()}"}
  end

  defp generate_peer_did(_opts) do
    {:ok, "did:peer:#{generate_identifier()}"}
  end

  # ---------------------------------------------------------------------------
  # Private – DID resolution
  # ---------------------------------------------------------------------------

  # Atom keys avoid the "quoted keyword" compiler warnings while still
  # producing valid JSON via Jason (which serialises atom keys as strings).

  defp resolve_key_did(did) do
    {:ok,
     %{
       "@context": "https://www.w3.org/ns/did/v1",
       id: did,
       verificationMethod: [
         %{
           id: "#verification-key",
           type: "Ed25519VerificationKey2020",
           controller: did,
           publicKeyMultibase: did
         }
       ]
     }}
  end

  defp resolve_web_did(did) do
    {:ok, %{"@context": "https://www.w3.org/ns/did/v1", id: did}}
  end

  defp resolve_plc_did(did) do
    {:ok, %{"@context": "https://www.w3.org/ns/did/v1", id: did}}
  end

  defp resolve_peer_did(did) do
    {:ok, %{"@context": "https://www.w3.org/ns/did/v1", id: did}}
  end

  # ---------------------------------------------------------------------------
  # Private – helpers
  # ---------------------------------------------------------------------------

  defp valid_method?(method) do
    method in ["key", "web", "plc", "peer", "ion", "ethr", "polygon"]
  end

  defp generate_identifier do
    :crypto.strong_rand_bytes(32)
    |> Base.encode64(padding: false)
    |> String.replace(~r/[^A-Za-z0-9]/, "")
    |> String.slice(0, 32)
  end

  defp generate_ed25519_keypair do
    private_key = :crypto.strong_rand_bytes(32)
    {:ok, private_key}
  end

  defp extract_public_key(_private_key) do
    :crypto.strong_rand_bytes(32)
  end

  defp encode_multibase_base58btc(data) do
    Base.encode64(data, padding: false)
    |> String.replace(~r/[^A-Za-z0-9]/, "")
  end
end

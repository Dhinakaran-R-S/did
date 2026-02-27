defmodule Alem.LocalFirst.SqldSchema do
  @moduledoc """
  Bootstraps the sqld (LibSQL on Linode) schema on app startup.
  Creates tables if they don't exist.
  """

  require Logger

  @sqld_url "http://172.235.17.68:8080"

  def setup do
    Logger.info("[SqldSchema] Bootstrapping sqld schema...")

    sql = """
    CREATE TABLE IF NOT EXISTS documents (
      id           TEXT PRIMARY KEY,
      user_id      TEXT NOT NULL,
      tenant_id    TEXT NOT NULL DEFAULT 'default',
      filename     TEXT NOT NULL,
      content_type TEXT,
      object_key   TEXT,
      content_hash TEXT,
      text_content TEXT,
      metadata     TEXT DEFAULT '{}',
      status       TEXT DEFAULT 'completed',
      inserted_at  TEXT NOT NULL,
      updated_at   TEXT NOT NULL
    )
    """

    index1 = "CREATE INDEX IF NOT EXISTS idx_docs_user ON documents (user_id)"
    index2 = "CREATE INDEX IF NOT EXISTS idx_docs_updated ON documents (updated_at)"

    statements = [sql, index1, index2]

    body = Jason.encode!(%{
      requests: Enum.map(statements, fn s ->
        %{type: "execute", stmt: %{sql: String.trim(s)}}
      end) ++ [%{type: "close"}]
    })

    case Req.post("#{@sqld_url}/v3/pipeline",
      body: body,
      headers: [{"content-type", "application/json"}],
      receive_timeout: 10_000
    ) do
      {:ok, %{status: 200, body: resp}} ->
        errors = (resp["results"] || []) |> Enum.filter(&(&1["type"] == "error"))
        if errors == [] do
          Logger.info("[SqldSchema] sqld schema setup complete")
        else
          Logger.error("[SqldSchema] ❌ Errors: #{inspect(errors)}")
        end
      {:ok, %{status: status, body: body}} ->
        Logger.error("[SqldSchema] ❌ HTTP #{status}: #{inspect(body)}")
      {:error, reason} ->
        Logger.error("[SqldSchema] ❌ Failed: #{inspect(reason)}")
    end
  end
end

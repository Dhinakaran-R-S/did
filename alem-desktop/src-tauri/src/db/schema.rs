// src-tauri/src/db/schema.rs
use anyhow::Result;
use libsql::Connection;

pub async fn run_migrations(conn: &Connection) -> Result<()> {
    // schema_migrations table
    conn.execute_batch("
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version    INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
    ").await?;

    let mut rows = conn.query(
        "SELECT COALESCE(MAX(version), 0) FROM schema_migrations", ()
    ).await?;

    let version: i64 = if let Some(row) = rows.next().await? {
        row.get(0).unwrap_or(0)
    } else {
        0
    };

    if version < 1 {
        // libsql execute_batch runs the whole string as a transaction
        conn.execute_batch("
            CREATE TABLE IF NOT EXISTS local_identity (
                id                  TEXT PRIMARY KEY DEFAULT 'singleton',
                user_id             TEXT,
                tenant_id           TEXT NOT NULL DEFAULT 'default',
                username            TEXT,
                email               TEXT,
                did                 TEXT UNIQUE,
                did_public_key      TEXT,
                pleroma_account_id  TEXT,
                server_url          TEXT NOT NULL DEFAULT 'http://localhost:4000',
                last_sync_at        TEXT,
                created_at          TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS documents (
                id              TEXT PRIMARY KEY,
                user_id         TEXT NOT NULL,
                tenant_id       TEXT NOT NULL DEFAULT 'default',
                filename        TEXT NOT NULL,
                content_type    TEXT,
                file_size       INTEGER,
                content_hash    TEXT,
                local_path      TEXT,
                object_key      TEXT,
                text_content    TEXT,
                metadata        TEXT NOT NULL DEFAULT '{}',
                tags            TEXT NOT NULL DEFAULT '[]',
                status          TEXT NOT NULL DEFAULT 'local',
                local_version   INTEGER NOT NULL DEFAULT 1,
                server_version  INTEGER NOT NULL DEFAULT 0,
                is_synced       INTEGER NOT NULL DEFAULT 0,
                needs_upload    INTEGER NOT NULL DEFAULT 1,
                needs_download  INTEGER NOT NULL DEFAULT 0,
                sync_error      TEXT,
                last_synced_at  TEXT,
                created_at      TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at      TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE INDEX IF NOT EXISTS idx_docs_user   ON documents(user_id);
            CREATE INDEX IF NOT EXISTS idx_docs_status ON documents(status);
            CREATE INDEX IF NOT EXISTS idx_docs_upload ON documents(needs_upload)
                WHERE needs_upload = 1;

            CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
                id            UNINDEXED,
                filename,
                text_content,
                content       = 'documents',
                content_rowid = 'rowid'
            );

            CREATE TRIGGER IF NOT EXISTS docs_fts_insert AFTER INSERT ON documents BEGIN
                INSERT INTO documents_fts(id, filename, text_content)
                VALUES (new.id, new.filename, new.text_content);
            END;

            CREATE TRIGGER IF NOT EXISTS docs_fts_update AFTER UPDATE ON documents BEGIN
                UPDATE documents_fts
                SET    filename     = new.filename,
                       text_content = new.text_content
                WHERE  id = new.id;
            END;

            CREATE TRIGGER IF NOT EXISTS docs_fts_delete AFTER DELETE ON documents BEGIN
                DELETE FROM documents_fts WHERE id = old.id;
            END;

            CREATE TABLE IF NOT EXISTS offline_operations (
                id          TEXT PRIMARY KEY,
                user_id     TEXT NOT NULL,
                op_type     TEXT NOT NULL,
                payload     TEXT NOT NULL DEFAULT '{}',
                status      TEXT NOT NULL DEFAULT 'pending',
                retry_count INTEGER NOT NULL DEFAULT 0,
                error_msg   TEXT,
                created_at  TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE INDEX IF NOT EXISTS idx_ops_status
                ON offline_operations(user_id, status);

            INSERT INTO schema_migrations(version) VALUES (1);
        ").await?;
    }

    Ok(())
}
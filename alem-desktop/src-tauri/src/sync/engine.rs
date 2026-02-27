// src-tauri/src/sync/engine.rs
// Fully rewritten for libsql — all db.lock() / rusqlite::params! removed.
// Each sync operation gets its own libsql::Connection (cheap, from the shared Database).

use crate::commands::auth::get_oauth_token;
use anyhow::{Context, Result};
use libsql::Value;
use serde_json::Value as Json;
use std::time::Duration;
use tauri::{AppHandle, Manager};

pub async fn start(app: AppHandle) {
    tokio::time::sleep(Duration::from_secs(3)).await;
    loop {
        if let Err(e) = run_sync_cycle(&app).await {
            log::warn!("[sync] Cycle error: {e}");
        }
        tokio::time::sleep(Duration::from_secs(30)).await;
    }
}

pub async fn run_once(app: &AppHandle) -> Result<()> {
    run_sync_cycle(app).await
}

async fn run_sync_cycle(app: &AppHandle) -> Result<()> {
    let token = match get_oauth_token().await.ok().flatten() {
        Some(t) => t,
        None    => return Ok(()),
    };

    let state      = app.state::<crate::AppState>();
    let conn       = state.db.connect()?;
    let server_url = query_server_url(&conn).await;

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(8))
        .build()?;

    if client.get(format!("{server_url}/api/v1/health")).send().await.is_err() {
        log::debug!("[sync] Server unreachable — skipping");
        return Ok(());
    }

    process_pending_ops(app, &client, &server_url, &token).await?;
    pull_server_changes(app, &client, &server_url, &token).await?;

    Ok(())
}

// ── Helpers ──────────────────────────────────────────────────────────────────

async fn query_server_url(conn: &libsql::Connection) -> String {
    if let Ok(mut rows) = conn.query(
        "SELECT server_url FROM local_identity WHERE id='singleton'", ()
    ).await {
        if let Ok(Some(row)) = rows.next().await {
            if let Ok(Value::Text(s)) = row.get_value(0) { return s; }
        }
    }
    "http://localhost:4000".into()
}

fn text(row: &libsql::Row, i: i32) -> Option<String> {
    match row.get_value(i).ok()? {
        Value::Text(s) => Some(s),
        _ => None,
    }
}

// ── Pending operation queue ───────────────────────────────────────────────────

async fn process_pending_ops(
    app: &AppHandle,
    client: &reqwest::Client,
    server_url: &str,
    token: &str,
) -> Result<()> {
    // Snapshot the pending ops — use a fresh connection so we don't hold it
    // across await points in upload_document
    let ops = {
        let state = app.state::<crate::AppState>();
        let conn  = state.db.connect()?;
        let mut rows = conn.query(
            "SELECT id, op_type, payload
             FROM offline_operations
             WHERE status = 'pending' AND retry_count < 5
             ORDER BY created_at ASC LIMIT 20",
            (),
        ).await?;

        let mut v = Vec::new();
        while let Some(row) = rows.next().await? {
            let id      = text(&row, 0).unwrap_or_default();
            let op_type = text(&row, 1).unwrap_or_default();
            let payload = text(&row, 2).unwrap_or_else(|| "{}".into());
            v.push((id, op_type, payload));
        }
        v
    };

    for (op_id, op_type, payload_str) in ops {
        let payload: Json = serde_json::from_str(&payload_str).unwrap_or(Json::Null);

        let result = match op_type.as_str() {
            "upload_document" => upload_document(app, client, server_url, token, &payload).await,
            "delete_document" => delete_document_on_server(client, server_url, token, &payload).await,
            other => { log::warn!("[sync] Unknown op: {other}"); Ok(()) }
        };

        // Update op status — new connection per update to avoid lock contention
        let state = app.state::<crate::AppState>();
        let conn  = state.db.connect()?;
        match result {
            Ok(_) => {
                conn.execute(
                    "UPDATE offline_operations SET status='done', updated_at=datetime('now') WHERE id=?1",
                    libsql::params![op_id],
                ).await?;
            }
            Err(e) => {
                log::warn!("[sync] Op {op_id} failed: {e}");
                conn.execute(
                    "UPDATE offline_operations
                     SET retry_count = retry_count + 1, status = 'failed',
                         error_msg = ?1, updated_at = datetime('now')
                     WHERE id = ?2",
                    libsql::params![e.to_string(), op_id],
                ).await?;
            }
        }
    }

    Ok(())
}

async fn upload_document(
    app: &AppHandle,
    client: &reqwest::Client,
    server_url: &str,
    token: &str,
    payload: &Json,
) -> Result<()> {
    let doc_id = payload["doc_id"].as_str().context("Missing doc_id")?;

    let (filename, local_path, content_type, metadata) = {
        let state = app.state::<crate::AppState>();
        let conn  = state.db.connect()?;
        let mut rows = conn.query(
            "SELECT filename, local_path, content_type, metadata FROM documents WHERE id=?1",
            libsql::params![doc_id],
        ).await?;

        if let Some(row) = rows.next().await? {
            (
                text(&row, 0).unwrap_or_default(),
                text(&row, 1),
                text(&row, 2),
                text(&row, 3).unwrap_or_else(|| "{}".into()),
            )
        } else {
            anyhow::bail!("Document {doc_id} not found in local DB");
        }
    };

    let local_path = local_path.context("Document has no local_path")?;

    // 1. Get presigned S3 URL from Phoenix
    let url_resp: Json = client
        .post(format!("{server_url}/api/v1/sync/upload-url"))
        .bearer_auth(token)
        .json(&serde_json::json!({ "doc_id": doc_id, "filename": filename }))
        .send().await?
        .json().await?;

    let upload_url = url_resp["upload_url"].as_str().context("No upload_url")?;
    let object_key = url_resp["object_key"].as_str().context("No object_key")?;

    // 2. Upload file bytes directly to S3 (presigned PUT)
    let ct         = content_type.unwrap_or_else(|| "application/octet-stream".into());
    let file_bytes = tokio::fs::read(&local_path).await
        .with_context(|| format!("Cannot read {local_path}"))?;
        
        
        client
    .put(upload_url)
    .body(file_bytes)
    .send().await?
    .error_for_status()?;

    // 3. Tell Phoenix the upload is done
    client
        .post(format!("{server_url}/api/v1/sync/apply"))
        .bearer_auth(token)
        .json(&serde_json::json!({
            "changes": [{
                "type": "create_document",
                "id":   doc_id,
                "data": {
                    "id":           doc_id,
                    "filename":     filename,
                    "content_type": ct,
                    "object_key":   object_key,
                    "metadata":     serde_json::from_str::<Json>(&metadata).unwrap_or(Json::Null)
                }
            }]
        }))
        .send().await?
        .error_for_status()?;

    // 4. Mark local record as synced
    {
        let state = app.state::<crate::AppState>();
        let conn  = state.db.connect()?;
        conn.execute(
            "UPDATE documents
             SET status='synced', object_key=?1, is_synced=1,
                 needs_upload=0, last_synced_at=datetime('now'), updated_at=datetime('now')
             WHERE id=?2",
            libsql::params![object_key, doc_id],
        ).await?;
    }

    log::info!("[sync] Uploaded {doc_id} → {object_key}");
    Ok(())
}

async fn delete_document_on_server(
    client: &reqwest::Client,
    server_url: &str,
    token: &str,
    payload: &Json,
) -> Result<()> {
    let doc_id = payload["doc_id"].as_str().context("Missing doc_id")?;
    client
        .post(format!("{server_url}/api/v1/sync/apply"))
        .bearer_auth(token)
        .json(&serde_json::json!({
            "changes": [{"type": "delete_document", "id": doc_id, "data": {"id": doc_id}}]
        }))
        .send().await?
        .error_for_status()?;
    Ok(())
}

// ── Pull server changes ───────────────────────────────────────────────────────

async fn pull_server_changes(
    app: &AppHandle,
    client: &reqwest::Client,
    server_url: &str,
    token: &str,
) -> Result<()> {
    let since = {
        let state = app.state::<crate::AppState>();
        let conn  = state.db.connect()?;
        let mut rows = conn.query(
            "SELECT COALESCE(last_sync_at,'2000-01-01T00:00:00Z')
             FROM local_identity WHERE id='singleton'",
            (),
        ).await?;
        if let Some(row) = rows.next().await? {
            text(&row, 0).unwrap_or_else(|| "2000-01-01T00:00:00Z".into())
        } else {
            "2000-01-01T00:00:00Z".into()
        }
    };

    let resp: Json = client
        .get(format!("{server_url}/api/v1/sync/changes"))
        .bearer_auth(token)
        .query(&[("since", &since)])
        .send().await?
        .json().await?;

    let changes = resp["changes"].as_array().cloned().unwrap_or_default();
    log::info!("[sync] Pulled {} changes from server", changes.len());

    for change in &changes {
        apply_server_change(app, change).await?;
    }

    // Update last_sync_at
    let state = app.state::<crate::AppState>();
    let conn  = state.db.connect()?;
    conn.execute(
        "UPDATE local_identity SET last_sync_at=datetime('now') WHERE id='singleton'", ()
    ).await?;

    Ok(())
}

async fn apply_server_change(app: &AppHandle, change: &Json) -> Result<()> {
    let state = app.state::<crate::AppState>();
    let conn  = state.db.connect()?;
    let data  = &change["data"];

    match change["type"].as_str().unwrap_or("") {
        "document_updated" | "document_created" => {
            let id = data["id"].as_str().unwrap_or("");

            let mut rows = conn.query(
                "SELECT COUNT(*) FROM documents WHERE id=?1",
                libsql::params![id],
            ).await?;

            let exists = if let Some(row) = rows.next().await? {
                matches!(row.get_value(0), Ok(Value::Integer(n)) if n > 0)
            } else { false };

            if !exists {
                conn.execute(
                    "INSERT OR IGNORE INTO documents
                     (id, user_id, tenant_id, filename, content_type, object_key,
                      status, needs_upload, needs_download, is_synced)
                     VALUES (?1,?2,?3,?4,?5,?6,'synced',0,1,1)",
                    libsql::params![
                        id,
                        data["user_id"].as_str().unwrap_or(""),
                        data["tenant_id"].as_str().unwrap_or("default"),
                        data["filename"].as_str().unwrap_or(""),
                        data["content_type"].as_str().unwrap_or(""),
                        data["object_key"].as_str().unwrap_or(""),
                    ],
                ).await?;
            } else {
                conn.execute(
                    "UPDATE documents
                     SET object_key=?1, status='synced', is_synced=1,
                         needs_upload=0, last_synced_at=datetime('now')
                     WHERE id=?2",
                    libsql::params![
                        data["object_key"].as_str().unwrap_or(""),
                        id,
                    ],
                ).await?;
            }
        }
        "document_deleted" => {
            let id = data["id"].as_str().unwrap_or("");
            conn.execute(
                "UPDATE documents SET status='deleted' WHERE id=?1",
                libsql::params![id],
            ).await?;
        }
        other => log::debug!("[sync] Unknown change type: {other}"),
    }

    Ok(())
}
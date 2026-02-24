// src-tauri/src/commands/sync.rs
use crate::{db::models::SyncStatus, AppState};
use tauri::{AppHandle, State};

#[tauri::command]
pub async fn get_sync_status(state: State<'_, AppState>) -> Result<SyncStatus, String> {
    let conn = state.db.connect().map_err(|e| e.to_string())?;

    // pending count
    let mut rows = conn.query(
        "SELECT COUNT(*) FROM offline_operations WHERE status='pending'", ()
    ).await.map_err(|e| e.to_string())?;
    let pending: i64 = if let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        match row.get_value(0).ok() { Some(libsql::Value::Integer(n)) => n, _ => 0 }
    } else { 0 };

    // failed count
    let mut rows = conn.query(
        "SELECT COUNT(*) FROM offline_operations WHERE status='failed'", ()
    ).await.map_err(|e| e.to_string())?;
    let failed: i64 = if let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        match row.get_value(0).ok() { Some(libsql::Value::Integer(n)) => n, _ => 0 }
    } else { 0 };

    // last_sync_at
    let mut rows = conn.query(
        "SELECT last_sync_at FROM local_identity WHERE id='singleton'", ()
    ).await.map_err(|e| e.to_string())?;
    let last_sync: Option<String> = if let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        match row.get_value(0).ok() { Some(libsql::Value::Text(s)) => Some(s), _ => None }
    } else { None };

    Ok(SyncStatus {
        is_syncing: false,
        last_sync_at: last_sync,
        pending_count: pending,
        failed_count: failed,
        connection_online: true,
    })
}

#[tauri::command]
pub async fn trigger_sync(app: AppHandle) -> Result<String, String> {
    tauri::async_runtime::spawn(async move {
        if let Err(e) = crate::sync::engine::run_once(&app).await {
            log::warn!("[sync] Manual trigger failed: {e}");
        }
    });
    Ok("Sync triggered".to_string())
}

#[tauri::command]
pub async fn get_pending_operations(state: State<'_, AppState>) -> Result<serde_json::Value, String> {
    let conn = state.db.connect().map_err(|e| e.to_string())?;
    let mut rows = conn.query(
        "SELECT id, op_type, status, retry_count, error_msg, created_at
         FROM offline_operations WHERE status IN ('pending','failed')
         ORDER BY created_at DESC LIMIT 50",
        (),
    ).await.map_err(|e| e.to_string())?;

    let mut ops: Vec<serde_json::Value> = Vec::new();
    while let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        use libsql::Value;
        let s = |i| match row.get_value(i).ok() { Some(Value::Text(s)) => s, _ => String::new() };
        let n = |i| match row.get_value(i).ok() { Some(Value::Integer(n)) => n, _ => 0 };
        ops.push(serde_json::json!({
            "id":          s(0),
            "op_type":     s(1),
            "status":      s(2),
            "retry_count": n(3),
            "error_msg":   match row.get_value(4).ok() { Some(Value::Text(s)) => serde_json::Value::String(s), _ => serde_json::Value::Null },
            "created_at":  s(5),
        }));
    }

    let count = ops.len();
    Ok(serde_json::json!({ "operations": ops, "count": count }))
}

#[tauri::command]
pub async fn retry_failed_operations(
    state: State<'_, AppState>,
    app: AppHandle,
) -> Result<u64, String> {
    let conn = state.db.connect().map_err(|e| e.to_string())?;
    let affected = conn.execute(
        "UPDATE offline_operations
         SET status='pending', retry_count=0, error_msg=NULL, updated_at=datetime('now')
         WHERE status='failed'",
        (),
    ).await.map_err(|e| e.to_string())?;

    tauri::async_runtime::spawn(async move {
        let _ = crate::sync::engine::run_once(&app).await;
    });

    Ok(affected)
}
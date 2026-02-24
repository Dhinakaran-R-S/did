// src-tauri/src/commands/documents.rs
use crate::{db::models::{Document, row_to_document}, AppState};
use serde::Deserialize;
use tauri::State;
use uuid::Uuid;

#[derive(Debug, Deserialize)]
pub struct CreateDocumentInput {
    pub filename:     String,
    pub content_type: String,
    pub local_path:   String,
    pub file_size:    i64,
    pub content_hash: String,
    pub text_content: Option<String>,
    pub metadata:     Option<serde_json::Value>,
    pub tags:         Option<Vec<String>>,
}

#[tauri::command]
pub async fn create_document(
    input: CreateDocumentInput,
    state: State<'_, AppState>,
) -> Result<Document, String> {
    let conn = state.db.connect().map_err(|e| e.to_string())?;

    let id       = Uuid::new_v4().to_string();
    let metadata = serde_json::to_string(&input.metadata.unwrap_or(serde_json::json!({}))).unwrap_or_else(|_| "{}".into());
    let tags     = serde_json::to_string(&input.tags.unwrap_or_default()).unwrap_or_else(|_| "[]".into());

    // Read identity from libsql
    let mut id_rows = conn.query(
        "SELECT COALESCE(user_id,'anonymous'), COALESCE(tenant_id,'default')
         FROM local_identity WHERE id='singleton'",
        (),
    ).await.map_err(|e| e.to_string())?;

    let (user_id, tenant_id) = if let Some(row) = id_rows.next().await.map_err(|e| e.to_string())? {
        use libsql::Value;
        let uid = match row.get_value(0).ok() { Some(Value::Text(s)) => s, _ => "anonymous".into() };
        let tid = match row.get_value(1).ok() { Some(Value::Text(s)) => s, _ => "default".into()   };
        (uid, tid)
    } else {
        ("anonymous".into(), "default".into())
    };

    conn.execute(
        "INSERT INTO documents (
             id, user_id, tenant_id, filename, content_type, file_size,
             content_hash, local_path, text_content, metadata, tags,
             status, needs_upload
         ) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,'local',1)",
        libsql::params![
            id.clone(), user_id.clone(), tenant_id,
            input.filename, input.content_type, input.file_size,
            input.content_hash, input.local_path,
            input.text_content.unwrap_or_default(), metadata, tags,
        ],
    ).await.map_err(|e| format!("Insert failed: {e}"))?;

    // Queue upload operation
    let op_id   = Uuid::new_v4().to_string();
    let payload = format!("{{\"doc_id\":\"{id}\"}}");
    conn.execute(
        "INSERT INTO offline_operations (id, user_id, op_type, payload)
         VALUES (?1, ?2, 'upload_document', ?3)",
        libsql::params![op_id, user_id, payload],
    ).await.map_err(|e| format!("Queue op failed: {e}"))?;

    get_document(id, state).await
}

#[tauri::command]
pub async fn get_documents(state: State<'_, AppState>) -> Result<Vec<Document>, String> {
    let conn = state.db.connect().map_err(|e| e.to_string())?;
    let mut rows = conn.query(
        "SELECT id, user_id, tenant_id, filename, content_type, file_size, content_hash,
                local_path, object_key, text_content, metadata, tags, status,
                local_version, server_version, is_synced, needs_upload, needs_download,
                sync_error, last_synced_at, created_at, updated_at
         FROM documents WHERE status != 'deleted' ORDER BY created_at DESC",
        (),
    ).await.map_err(|e| e.to_string())?;

    let mut docs = Vec::new();
    while let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        if let Ok(doc) = row_to_document(&row) { docs.push(doc); }
    }
    Ok(docs)
}

#[tauri::command]
pub async fn get_document(id: String, state: State<'_, AppState>) -> Result<Document, String> {
    let conn = state.db.connect().map_err(|e| e.to_string())?;
    let mut rows = conn.query(
        "SELECT id, user_id, tenant_id, filename, content_type, file_size, content_hash,
                local_path, object_key, text_content, metadata, tags, status,
                local_version, server_version, is_synced, needs_upload, needs_download,
                sync_error, last_synced_at, created_at, updated_at
         FROM documents WHERE id = ?1",
        libsql::params![id],
    ).await.map_err(|e| e.to_string())?;

    if let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        row_to_document(&row).map_err(|e| e.to_string())
    } else {
        Err(format!("Document not found"))
    }
}

#[tauri::command]
pub async fn search_documents(query: String, state: State<'_, AppState>) -> Result<Vec<Document>, String> {
    let conn = state.db.connect().map_err(|e| e.to_string())?;
    let mut rows = conn.query(
        "SELECT d.id, d.user_id, d.tenant_id, d.filename, d.content_type, d.file_size, d.content_hash,
                d.local_path, d.object_key, d.text_content, d.metadata, d.tags, d.status,
                d.local_version, d.server_version, d.is_synced, d.needs_upload, d.needs_download,
                d.sync_error, d.last_synced_at, d.created_at, d.updated_at
         FROM documents d
         JOIN documents_fts fts ON d.id = fts.id
         WHERE d.status != 'deleted' AND documents_fts MATCH ?1
         ORDER BY rank",
        libsql::params![query],
    ).await.map_err(|e| e.to_string())?;

    let mut docs = Vec::new();
    while let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        if let Ok(doc) = row_to_document(&row) { docs.push(doc); }
    }
    Ok(docs)
}

#[tauri::command]
pub async fn update_document(
    id: String,
    filename: Option<String>,
    _metadata: Option<serde_json::Value>,
    _tags: Option<Vec<String>>,
    state: State<'_, AppState>,
) -> Result<Document, String> {
    if let Some(name) = filename {
        let conn = state.db.connect().map_err(|e| e.to_string())?;
        conn.execute(
            "UPDATE documents
             SET filename = ?1, local_version = local_version + 1,
                 needs_upload = 1, is_synced = 0, status = 'local',
                 updated_at = datetime('now')
             WHERE id = ?2",
            libsql::params![name, id.clone()],
        ).await.map_err(|e| format!("Update failed: {e}"))?;
    }
    get_document(id, state).await
}

#[tauri::command]
pub async fn delete_document(id: String, state: State<'_, AppState>) -> Result<(), String> {
    let conn = state.db.connect().map_err(|e| e.to_string())?;

    let mut rows = conn.query(
        "SELECT user_id FROM documents WHERE id = ?1",
        libsql::params![id.clone()],
    ).await.map_err(|e| e.to_string())?;

    let user_id = if let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        match row.get_value(0).ok() {
            Some(libsql::Value::Text(s)) => s,
            _ => return Err("User ID not found".into()),
        }
    } else {
        return Err(format!("Document {id} not found"));
    };

    conn.execute(
        "UPDATE documents SET status = 'deleted', updated_at = datetime('now') WHERE id = ?1",
        libsql::params![id.clone()],
    ).await.map_err(|e| format!("Delete failed: {e}"))?;

    let op_id   = Uuid::new_v4().to_string();
    let payload = format!("{{\"doc_id\":\"{id}\"}}");
    conn.execute(
        "INSERT INTO offline_operations (id, user_id, op_type, payload)
         VALUES (?1, ?2, 'delete_document', ?3)",
        libsql::params![op_id, user_id, payload],
    ).await.map_err(|e| format!("Queue delete failed: {e}"))?;

    Ok(())
}
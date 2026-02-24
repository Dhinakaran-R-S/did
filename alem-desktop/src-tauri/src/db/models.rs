// src-tauri/src/db/models.rs
// Unchanged structurally — but now populated from libsql::Row instead of rusqlite::Row
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Document {
    pub id: String,
    pub user_id: String,
    pub tenant_id: String,
    pub filename: String,
    pub content_type: Option<String>,
    pub file_size: Option<i64>,
    pub content_hash: Option<String>,
    pub local_path: Option<String>,
    pub object_key: Option<String>,
    pub text_content: Option<String>,
    pub metadata: serde_json::Value,
    pub tags: Vec<String>,
    pub status: String,
    pub local_version: i32,
    pub server_version: i32,
    pub is_synced: bool,
    pub needs_upload: bool,
    pub needs_download: bool,
    pub sync_error: Option<String>,
    pub last_synced_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocalIdentity {
    pub user_id: Option<String>,
    pub tenant_id: String,
    pub username: Option<String>,
    pub email: Option<String>,
    pub did: Option<String>,
    pub did_public_key: Option<String>,
    pub pleroma_account_id: Option<String>,
    pub server_url: String,
    pub last_sync_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OfflineOperation {
    pub id: String,
    pub user_id: String,
    pub op_type: String,
    pub payload: serde_json::Value,
    pub status: String,
    pub retry_count: i32,
    pub error_msg: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DIDResult {
    pub did: String,
    pub public_key_multibase: String,
    // private key is NEVER returned — stored only in OS keychain
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncStatus {
    pub is_syncing: bool,
    pub last_sync_at: Option<String>,
    pub pending_count: i64,
    pub failed_count: i64,
    pub connection_online: bool,
}

/// Helper: convert libsql::Row columns to a Document.
/// libsql::Row uses column index + Value enum, not typed closures.
pub fn row_to_document(row: &libsql::Row) -> anyhow::Result<Document> {
    use libsql::Value;

    fn get_str(row: &libsql::Row, idx: i32) -> Option<String> {
        match row.get_value(idx).ok()? {
            Value::Text(s) => Some(s),
            _ => None,
        }
    }
    fn get_i64(row: &libsql::Row, idx: i32) -> Option<i64> {
        match row.get_value(idx).ok()? {
            Value::Integer(i) => Some(i),
            _ => None,
        }
    }
    fn get_i32(row: &libsql::Row, idx: i32) -> i32 {
        get_i64(row, idx).unwrap_or(0) as i32
    }
    fn get_bool(row: &libsql::Row, idx: i32) -> bool {
        get_i64(row, idx).unwrap_or(0) != 0
    }

    let metadata_str = get_str(row, 10).unwrap_or_else(|| "{}".into());
    let tags_str     = get_str(row, 11).unwrap_or_else(|| "[]".into());

    Ok(Document {
        id:             get_str(row, 0).unwrap_or_default(),
        user_id:        get_str(row, 1).unwrap_or_default(),
        tenant_id:      get_str(row, 2).unwrap_or_default(),
        filename:       get_str(row, 3).unwrap_or_default(),
        content_type:   get_str(row, 4),
        file_size:      get_i64(row, 5),
        content_hash:   get_str(row, 6),
        local_path:     get_str(row, 7),
        object_key:     get_str(row, 8),
        text_content:   get_str(row, 9),
        metadata:       serde_json::from_str(&metadata_str).unwrap_or(serde_json::json!({})),
        tags:           serde_json::from_str(&tags_str).unwrap_or_default(),
        status:         get_str(row, 12).unwrap_or_else(|| "local".into()),
        local_version:  get_i32(row, 13),
        server_version: get_i32(row, 14),
        is_synced:      get_bool(row, 15),
        needs_upload:   get_bool(row, 16),
        needs_download: get_bool(row, 17),
        sync_error:     get_str(row, 18),
        last_synced_at: get_str(row, 19),
        created_at:     get_str(row, 20).unwrap_or_default(),
        updated_at:     get_str(row, 21).unwrap_or_default(),
    })
}
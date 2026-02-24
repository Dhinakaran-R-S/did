// src-tauri/src/commands/auth.rs
use crate::AppState;
use keyring::Entry;
use serde::{Deserialize, Serialize};
use tauri::State;

const KEYRING_SERVICE: &str = "alem-desktop";
const OAUTH_KEY: &str = "oauth_token";

#[derive(Serialize, Deserialize)]
pub struct AuthResult {
    pub authenticated: bool,
    pub server_url: Option<String>,
    pub username: Option<String>,
}

#[tauri::command]
pub async fn store_oauth_token(
    token: String,
    server_url: String,
    username: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    // Token → OS keychain only
    let entry = Entry::new(KEYRING_SERVICE, OAUTH_KEY).map_err(|e| e.to_string())?;
    entry.set_password(&token).map_err(|e| e.to_string())?;

    // Non-sensitive info → libsql
    let conn = state.db.connect().map_err(|e| e.to_string())?;
    conn.execute(
        "INSERT INTO local_identity (id, server_url, username, updated_at)
         VALUES ('singleton', ?1, ?2, datetime('now'))
         ON CONFLICT(id) DO UPDATE SET
             server_url = excluded.server_url,
             username   = excluded.username,
             updated_at = datetime('now')",
        libsql::params![server_url, username],
    ).await.map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub async fn get_oauth_token() -> Result<Option<String>, String> {
    let entry = Entry::new(KEYRING_SERVICE, OAUTH_KEY).map_err(|e| e.to_string())?;
    match entry.get_password() {
        Ok(t)                          => Ok(Some(t)),
        Err(keyring::Error::NoEntry)   => Ok(None),
        Err(e)                         => Err(e.to_string()),
    }
}

#[tauri::command]
pub async fn clear_oauth_token() -> Result<(), String> {
    let entry = Entry::new(KEYRING_SERVICE, OAUTH_KEY).map_err(|e| e.to_string())?;
    entry.delete_credential().map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn is_authenticated(state: State<'_, AppState>) -> Result<AuthResult, String> {
    let token = match get_oauth_token().await? {
        Some(t) if !t.is_empty() => t,
        _ => return Ok(AuthResult { authenticated: false, server_url: None, username: None }),
    };
    let _ = token; // confirmed present

    let conn = state.db.connect().map_err(|e| e.to_string())?;
    let mut rows = conn.query(
        "SELECT server_url, username FROM local_identity WHERE id = 'singleton'",
        (),
    ).await.map_err(|e| e.to_string())?;

    if let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        use libsql::Value;
        let server_url = match row.get_value(0).ok() {
            Some(Value::Text(s)) => Some(s),
            _ => None,
        };
        let username = match row.get_value(1).ok() {
            Some(Value::Text(s)) => Some(s),
            _ => None,
        };
        Ok(AuthResult { authenticated: true, server_url, username })
    } else {
        Ok(AuthResult { authenticated: false, server_url: None, username: None })
    }
}
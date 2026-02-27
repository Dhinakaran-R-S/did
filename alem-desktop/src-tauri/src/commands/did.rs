// src-tauri/src/commands/did.rs
use crate::{db::models::DIDResult, AppState};
use ed25519_dalek::SigningKey;
use keyring::Entry;
use rand::rngs::OsRng;
use tauri::State;

const KEYRING_SERVICE: &str = "alem-desktop";

#[tauri::command]
pub async fn generate_did(state: State<'_, AppState>) -> Result<DIDResult, String> {
    let mut csprng  = OsRng;
    let signing_key = SigningKey::generate(&mut csprng);
    let verifying   = signing_key.verifying_key();

    // did:key multicodec prefix for Ed25519 = 0xed 0x01
    let mut prefixed = vec![0xed_u8, 0x01];
    prefixed.extend_from_slice(verifying.as_bytes());
    let multibase = format!("z{}", bs58::encode(&prefixed).into_string());
    let did       = format!("did:key:{multibase}");

    // Private key → OS keychain
    let priv_b64 = base64_simple(signing_key.as_bytes());
    Entry::new(KEYRING_SERVICE, &format!("did_priv_{did}"))
        .map_err(|e| e.to_string())?
        .set_password(&priv_b64)
        .map_err(|e| e.to_string())?;

    // DID + public key → libsql
    let conn = state.db.connect().map_err(|e| e.to_string())?;
    conn.execute(
        "UPDATE local_identity
         SET did = ?1, did_public_key = ?2, updated_at = datetime('now')
         WHERE id = 'singleton'",
        libsql::params![did.clone(), multibase.clone()],
    ).await.map_err(|e| e.to_string())?;

    Ok(DIDResult { did, public_key_multibase: multibase })
}

#[tauri::command]
pub async fn get_stored_did(state: State<'_, AppState>) -> Result<Option<DIDResult>, String> {
    let conn = state.db.connect().map_err(|e| e.to_string())?;
    let mut rows = conn.query(
        "SELECT did, did_public_key FROM local_identity
         WHERE id = 'singleton' AND did IS NOT NULL",
        (),
    ).await.map_err(|e| e.to_string())?;

    if let Some(row) = rows.next().await.map_err(|e| e.to_string())? {
        use libsql::Value;
        let did = match row.get_value(0).ok() {
            Some(Value::Text(s)) => s,
            _ => return Ok(None),
        };
        let public_key_multibase = match row.get_value(1).ok() {
            Some(Value::Text(s)) => s,
            _ => String::new(),
        };
        Ok(Some(DIDResult { did, public_key_multibase }))
    } else {
        Ok(None)
    }
}

#[tauri::command]
pub async fn validate_did(did: String) -> Result<bool, String> {
    Ok(did.starts_with("did:key:z") && did.len() > 12)
}


#[tauri::command]
pub async fn store_server_did(
    did: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    // Store server-generated DID in local SQLite
    // No private key — server holds the keypair
    let conn = state.db.connect().map_err(|e| e.to_string())?;
    conn.execute(
        "UPDATE local_identity
         SET did = ?1, did_public_key = ?2, updated_at = datetime('now')
         WHERE id = 'singleton'",
        libsql::params![
            did.clone(),
            did.replace("did:key:", "")  // public key is the multibase part
        ],
    ).await.map_err(|e| e.to_string())?;

    Ok(())
}


fn base64_simple(bytes: &[u8]) -> String {
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::new();
    for chunk in bytes.chunks(3) {
        let n = match chunk.len() {
            3 => ((chunk[0] as u32) << 16) | ((chunk[1] as u32) << 8) | chunk[2] as u32,
            2 => ((chunk[0] as u32) << 16) | ((chunk[1] as u32) << 8),
            _ => (chunk[0] as u32) << 16,
        };
        out.push(CHARS[((n >> 18) & 63) as usize] as char);
        out.push(CHARS[((n >> 12) & 63) as usize] as char);
        out.push(if chunk.len() > 1 { CHARS[((n >>  6) & 63) as usize] as char } else { '=' });
        out.push(if chunk.len() > 2 { CHARS[( n        & 63) as usize] as char } else { '=' });
    }
    out
}
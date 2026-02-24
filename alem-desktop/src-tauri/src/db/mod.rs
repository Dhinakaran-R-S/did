// src-tauri/src/db/mod.rs
pub mod models;
pub mod schema;

use anyhow::Result;
use libsql::{Builder, Database};

/// Open (or create) a local embedded libsql database.
/// This is the standard local-only mode — SQLite-compatible, no network.
/// To enable Turso embedded replica sync, use open_with_replica() below instead.
pub async fn open(path: &str) -> Result<Database> {
    let db = Builder::new_local(path).build().await?;

    // Run schema migrations once on open
    let conn = db.connect()?;
    schema::run_migrations(&conn).await?;

    Ok(db)
}

/// Optional: open as an embedded replica syncing to a Turso remote.
/// Call this variant instead of open() if you want cloud backup/multi-device sync
/// handled natively by libsql without going through Phoenix.
///
/// ```
/// let db = db::open_with_replica(
///     "/path/to/local.db",
///     "libsql://your-db.turso.io",
///     "your-turso-auth-token",
/// ).await?;
/// ```
#[allow(dead_code)]
pub async fn open_with_replica(local_path: &str, remote_url: &str, auth_token: &str) -> Result<Database> {
    let db = Builder::new_remote_replica(local_path, remote_url.to_string(), auth_token.to_string())
        .sync_interval(std::time::Duration::from_secs(60))
        .build()
        .await?;

    let conn = db.connect()?;
    schema::run_migrations(&conn).await?;

    Ok(db)
}
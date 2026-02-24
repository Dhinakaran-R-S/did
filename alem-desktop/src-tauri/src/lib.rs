// src-tauri/src/lib.rs
mod commands;
mod db;
mod sync;

use std::sync::Arc;
use tauri::Manager;

/// AppState now holds an Arc<libsql::Database> instead of a rusqlite::Connection.
/// libsql::Database is cheaply clonable (Arc internally) and its connections are
/// async — no Mutex needed for multi-access safety.
pub struct AppState {
    pub db: Arc<libsql::Database>,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .setup(|app| {
            let data_dir = app.path().app_data_dir()
                .expect("Failed to resolve app data dir");
            std::fs::create_dir_all(&data_dir)?;

            let db_path = data_dir.join("alem.db");

            // Build the libsql Database on the tokio runtime that Tauri already runs
            let database = tauri::async_runtime::block_on(async {
                db::open(db_path.to_str().expect("Invalid path"))
                    .await
                    .expect("Failed to open libsql database")
            });

            let db = Arc::new(database);
            app.manage(AppState { db: Arc::clone(&db) });

            // Spawn background sync engine
            let app_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                sync::engine::start(app_handle).await;
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            // Auth
            commands::auth::store_oauth_token,
            commands::auth::get_oauth_token,
            commands::auth::clear_oauth_token,
            commands::auth::is_authenticated,
            // DID
            commands::did::generate_did,
            commands::did::get_stored_did,
            commands::did::validate_did,
            // Documents
            commands::documents::create_document,
            commands::documents::get_documents,
            commands::documents::get_document,
            commands::documents::update_document,
            commands::documents::delete_document,
            commands::documents::search_documents,
            // Files
            commands::files::store_file,
            commands::files::get_file_path,
            commands::files::delete_file,
            // Sync
            commands::sync::get_sync_status,
            commands::sync::trigger_sync,
            commands::sync::get_pending_operations,
            commands::sync::retry_failed_operations,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
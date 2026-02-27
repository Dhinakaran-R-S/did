// src-tauri/src/commands/files.rs
use crate::AppState;
use tauri::{AppHandle, Manager, State};
use uuid::Uuid;
use std::path::PathBuf;

#[tauri::command]
pub async fn store_file(
    source_path: String,
    filename: String,
    app: AppHandle,
    _state: State<'_, AppState>,
) -> Result<String, String> {
    let data_dir = app.path().app_data_dir()
        .map_err(|e| e.to_string())?;
    let files_dir = data_dir.join("files");
    tokio::fs::create_dir_all(&files_dir).await.map_err(|e| e.to_string())?;

    let ext = PathBuf::from(&filename)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| format!(".{e}"))
        .unwrap_or_default();

    let dest_name = format!("{}{}", Uuid::new_v4(), ext);
    let dest      = files_dir.join(&dest_name);

    tokio::fs::copy(&source_path, &dest).await.map_err(|e| e.to_string())?;

    Ok(dest.to_string_lossy().to_string())
}

#[tauri::command]
pub async fn get_file_path(
    local_path: String,
    _state: State<'_, AppState>,
) -> Result<String, String> {
    if tokio::fs::metadata(&local_path).await.is_ok() {
        Ok(local_path)
    } else {
        Err("File not found".into())
    }
}

#[tauri::command]
pub async fn delete_file(
    local_path: String,
    _state: State<'_, AppState>,
) -> Result<(), String> {
    tokio::fs::remove_file(&local_path).await.map_err(|e| e.to_string())
}
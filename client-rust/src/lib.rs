use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::spawn_local;
use web_sys::console;

mod database;
mod storage;
mod sync;
mod crypto;
mod api;
mod utils;

use database::LibSQLClient;
use storage::FileManager;
use sync::SyncEngine;
use crypto::DIDManager;
use api::ApiClient;
use utils::error::AlemError;

// Import the `console.log` function from the `web-sys` crate
#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = console)]
    fn log(s: &str);
}

// Define a macro for easier logging
macro_rules! console_log {
    ($($t:tt)*) => (log(&format_args!($($t)*).to_string()))
}

// Initialize the WASM module
#[wasm_bindgen(start)]
pub fn main() {
    console_log::init_with_level(log::Level::Info).expect("Failed to initialize logger");
    console_error_panic_hook::set_once();
    console_log!("Alem WASM client initialized");
}

// Main client class
#[wasm_bindgen]
pub struct AlemClient {
    user_id: String,
    tenant_id: String,
    db_client: LibSQLClient,
    file_manager: FileManager,
    sync_engine: SyncEngine,
    did_manager: DIDManager,
    api_client: ApiClient,
}

#[wasm_bindgen]
impl AlemClient {
    #[wasm_bindgen(constructor)]
    pub fn new(user_id: String) -> Result<AlemClient, JsValue> {
        let tenant_id = "default".to_string();
        
        let db_client = LibSQLClient::new(&user_id)?;
        let file_manager = FileManager::new(&user_id)?;
        let sync_engine = SyncEngine::new(&user_id, &tenant_id)?;
        let did_manager = DIDManager::new()?;
        let api_client = ApiClient::new()?;
        
        Ok(AlemClient {
            user_id,
            tenant_id,
            db_client,
            file_manager,
            sync_engine,
            did_manager,
            api_client,
        })
    }
    
    /// Initialize the local database
    #[wasm_bindgen]
    pub async fn init_database(&self) -> Result<(), JsValue> {
        console_log!("Initializing local database for user: {}", self.user_id);
        
        self.db_client.init().await
            .map_err(|e| JsValue::from_str(&format!("Database init failed: {}", e)))?;
        
        console_log!("Database initialized successfully");
        Ok(())
    }
    
    /// Create a new document
    #[wasm_bindgen]
    pub async fn create_document(&self, input: &JsValue) -> Result<JsValue, JsValue> {
        let document_input: DocumentInput = serde_wasm_bindgen::from_value(input.clone())?;
        
        console_log!("Creating document: {}", document_input.filename);
        
        // Generate document ID
        let doc_id = uuid::Uuid::new_v4().to_string();
        
        // Store file content
        let local_path = self.file_manager.store_file(
            &doc_id,
            &document_input.filename,
            &document_input.content
        ).await?;
        
        // Create document record
        let document = Document {
            id: doc_id.clone(),
            user_id: self.user_id.clone(),
            tenant_id: self.tenant_id.clone(),
            filename: document_input.filename,
            content_type: document_input.content_type,
            file_size: document_input.content.len() as i64,
            content_hash: self.calculate_content_hash(&document_input.content),
            local_path,
            is_cached_locally: true,
            local_version: 1,
            server_version: 0,
            is_synced: false,
            text_content: self.extract_text_content(&document_input.content, &document_input.content_type),
            metadata: document_input.metadata,
            tags: document_input.tags,
            status: "local".to_string(),
            needs_upload: true,
            needs_download: false,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        };
        
        // Save to database
        self.db_client.create_document(&document).await?;
        
        // Queue for sync
        self.sync_engine.queue_create_operation(&document).await?;
        
        console_log!("Document created successfully: {}", doc_id);
        
        serde_wasm_bindgen::to_value(&document)
            .map_err(|e| JsValue::from_str(&format!("Serialization error: {}", e)))
    }
    
    /// Get all documents for the user
    #[wasm_bindgen]
    pub async fn get_documents(&self) -> Result<JsValue, JsValue> {
        console_log!("Fetching documents for user: {}", self.user_id);
        
        let documents = self.db_client.get_documents(&self.user_id).await?;
        
        console_log!("Found {} documents", documents.len());
        
        serde_wasm_bindgen::to_value(&documents)
            .map_err(|e| JsValue::from_str(&format!("Serialization error: {}", e)))
    }
    
    /// Search documents by text content
    #[wasm_bindgen]
    pub async fn search_documents(&self, query: String) -> Result<JsValue, JsValue> {
        console_log!("Searching documents with query: {}", query);
        
        let results = self.db_client.search_documents(&self.user_id, &query).await?;
        
        console_log!("Found {} search results", results.len());
        
        serde_wasm_bindgen::to_value(&results)
            .map_err(|e| JsValue::from_str(&format!("Serialization error: {}", e)))
    }
    
    /// Get document content
    #[wasm_bindgen]
    pub async fn get_document_content(&self, document_id: String) -> Result<js_sys::Uint8Array, JsValue> {
        console_log!("Getting content for document: {}", document_id);
        
        let document = self.db_client.get_document(&document_id).await?;
        let content = self.file_manager.get_file_content(&document.local_path).await?;
        
        Ok(js_sys::Uint8Array::from(&content[..]))
    }
    
    /// Sync local changes to server
    #[wasm_bindgen]
    pub async fn sync_to_server(&self) -> Result<JsValue, JsValue> {
        console_log!("Starting sync to server");
        
        let result = self.sync_engine.sync_to_server().await?;
        
        console_log!("Sync to server completed: {} operations", result.operations_synced);
        
        serde_wasm_bindgen::to_value(&result)
            .map_err(|e| JsValue::from_str(&format!("Serialization error: {}", e)))
    }
    
    /// Sync server changes to local
    #[wasm_bindgen]
    pub async fn sync_from_server(&self) -> Result<JsValue, JsValue> {
        console_log!("Starting sync from server");
        
        let result = self.sync_engine.sync_from_server().await?;
        
        console_log!("Sync from server completed: {} changes applied", result.changes_applied);
        
        serde_wasm_bindgen::to_value(&result)
            .map_err(|e| JsValue::from_str(&format!("Serialization error: {}", e)))
    }
    
    /// Get sync status
    #[wasm_bindgen]
    pub async fn get_sync_status(&self) -> Result<JsValue, JsValue> {
        let status = self.sync_engine.get_status().await?;
        
        serde_wasm_bindgen::to_value(&status)
            .map_err(|e| JsValue::from_str(&format!("Serialization error: {}", e)))
    }
    
    /// Generate a new DID
    #[wasm_bindgen]
    pub async fn generate_did(&self, method: Option<String>) -> Result<JsValue, JsValue> {
        console_log!("Generating DID with method: {:?}", method);
        
        let did_method = method.unwrap_or_else(|| "key".to_string());
        let result = self.did_manager.generate_did(&did_method).await?;
        
        console_log!("Generated DID: {}", result.did);
        
        serde_wasm_bindgen::to_value(&result)
            .map_err(|e| JsValue::from_str(&format!("Serialization error: {}", e)))
    }
    
    /// Set OAuth token for server communication
    #[wasm_bindgen]
    pub async fn set_oauth_token(&self, token: String) -> Result<(), JsValue> {
        console_log!("Setting OAuth token");
        
        self.api_client.set_token(token).await?;
        
        // Store token in local database
        self.db_client.store_oauth_token(&self.user_id, &self.api_client.get_token()).await?;
        
        Ok(())
    }
    
    /// Check if user is authenticated
    #[wasm_bindgen]
    pub async fn is_authenticated(&self) -> Result<bool, JsValue> {
        let token = self.db_client.get_oauth_token(&self.user_id).await?;
        Ok(token.is_some() && !self.is_token_expired(&token.unwrap()))
    }
    
    /// Get pending operations count
    #[wasm_bindgen]
    pub async fn get_pending_operations_count(&self) -> Result<u32, JsValue> {
        let count = self.sync_engine.get_pending_operations_count().await?;
        Ok(count)
    }
    
    /// Enable/disable auto-sync
    #[wasm_bindgen]
    pub fn set_auto_sync(&self, enabled: bool) {
        console_log!("Auto-sync {}", if enabled { "enabled" } else { "disabled" });
        self.sync_engine.set_auto_sync(enabled);
    }
}

// Private helper methods
impl AlemClient {
    fn calculate_content_hash(&self, content: &[u8]) -> String {
        use sha2::{Sha256, Digest};
        let mut hasher = Sha256::new();
        hasher.update(content);
        format!("{:x}", hasher.finalize())
    }
    
    fn extract_text_content(&self, content: &[u8], content_type: &str) -> Option<String> {
        if content_type.starts_with("text/") {
            String::from_utf8(content.to_vec()).ok()
        } else {
            None
        }
    }
    
    fn is_token_expired(&self, token: &str) -> bool {
        // Simple JWT expiration check
        // In a real implementation, you'd decode the JWT and check the exp claim
        false
    }
}

// Type definitions for JavaScript interop
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
pub struct DocumentInput {
    pub filename: String,
    pub content: Vec<u8>,
    pub content_type: String,
    pub metadata: std::collections::HashMap<String, String>,
    pub tags: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Document {
    pub id: String,
    pub user_id: String,
    pub tenant_id: String,
    pub filename: String,
    pub content_type: String,
    pub file_size: i64,
    pub content_hash: String,
    pub local_path: String,
    pub is_cached_locally: bool,
    pub local_version: i32,
    pub server_version: i32,
    pub is_synced: bool,
    pub text_content: Option<String>,
    pub metadata: std::collections::HashMap<String, String>,
    pub tags: Vec<String>,
    pub status: String,
    pub needs_upload: bool,
    pub needs_download: bool,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Serialize, Deserialize)]
pub struct SyncResult {
    pub operations_synced: u32,
    pub changes_applied: u32,
    pub conflicts_resolved: u32,
    pub errors: Vec<String>,
}

#[derive(Serialize, Deserialize)]
pub struct SyncStatus {
    pub is_syncing: bool,
    pub last_sync: Option<chrono::DateTime<chrono::Utc>>,
    pub pending_operations: u32,
    pub connection_status: String,
}

#[derive(Serialize, Deserialize)]
pub struct DIDResult {
    pub did: String,
    pub method: String,
    pub keypair: Option<std::collections::HashMap<String, String>>,
}
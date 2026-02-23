use wasm_bindgen::prelude::*;
use libsql::{Connection, Database};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use crate::utils::error::AlemError;
use crate::Document;

#[wasm_bindgen]
pub struct LibSQLClient {
    user_id: String,
    db: Option<Database>,
    conn: Option<Connection>,
}

impl LibSQLClient {
    pub fn new(user_id: &str) -> Result<Self, AlemError> {
        Ok(LibSQLClient {
            user_id: user_id.to_string(),
            db: None,
            conn: None,
        })
    }
    
    pub async fn init(&mut self) -> Result<(), AlemError> {
        // Create in-memory database for WASM
        let db_name = format!("file:alem_{}.db", self.user_id);
        
        let db = Database::open(&db_name).await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to open database: {}", e)))?;
        
        let conn = db.connect()
            .map_err(|e| AlemError::DatabaseError(format!("Failed to connect: {}", e)))?;
        
        // Run migrations
        self.run_migrations(&conn).await?;
        
        self.db = Some(db);
        self.conn = Some(conn);
        
        Ok(())
    }
    
    async fn run_migrations(&self, conn: &Connection) -> Result<(), AlemError> {
        // Create tables for local storage
        let migrations = vec![
            // Local users table
            r#"
            CREATE TABLE IF NOT EXISTS local_users (
                id TEXT PRIMARY KEY,
                tenant_id TEXT NOT NULL DEFAULT 'default',
                username TEXT,
                display_name TEXT,
                email TEXT,
                avatar_url TEXT,
                oauth_token TEXT,
                oauth_refresh_token TEXT,
                oauth_expires_at TEXT,
                pleroma_account_id TEXT,
                did TEXT,
                did_keypair TEXT, -- JSON string of encrypted keypair
                identity_type TEXT DEFAULT 'hybrid',
                last_sync_at TEXT,
                sync_token TEXT,
                is_online BOOLEAN DEFAULT FALSE,
                settings TEXT, -- JSON string
                status TEXT DEFAULT 'active',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            "#,
            
            // Local documents table
            r#"
            CREATE TABLE IF NOT EXISTS local_documents (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                tenant_id TEXT NOT NULL,
                filename TEXT NOT NULL,
                content_type TEXT,
                file_size INTEGER,
                content_hash TEXT,
                local_path TEXT,
                is_cached_locally BOOLEAN DEFAULT FALSE,
                local_version INTEGER DEFAULT 1,
                object_key TEXT,
                server_version INTEGER DEFAULT 1,
                is_synced BOOLEAN DEFAULT FALSE,
                last_synced_at TEXT,
                text_content TEXT,
                metadata TEXT, -- JSON string
                tags TEXT, -- JSON array string
                status TEXT DEFAULT 'local',
                sync_error TEXT,
                needs_upload BOOLEAN DEFAULT TRUE,
                needs_download BOOLEAN DEFAULT FALSE,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            "#,
            
            // Offline operations queue
            r#"
            CREATE TABLE IF NOT EXISTS offline_operations (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                type TEXT NOT NULL,
                data TEXT NOT NULL, -- JSON string
                status TEXT DEFAULT 'pending',
                retry_count INTEGER DEFAULT 0,
                error_message TEXT,
                last_retry_at TEXT,
                processed_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            "#,
            
            // Indexes for better performance
            "CREATE INDEX IF NOT EXISTS idx_local_documents_user_id ON local_documents(user_id)",
            "CREATE INDEX IF NOT EXISTS idx_local_documents_status ON local_documents(status)",
            "CREATE INDEX IF NOT EXISTS idx_local_documents_needs_sync ON local_documents(needs_upload, needs_download)",
            "CREATE INDEX IF NOT EXISTS idx_offline_operations_user_status ON offline_operations(user_id, status)",
            "CREATE INDEX IF NOT EXISTS idx_offline_operations_created ON offline_operations(created_at)",
            
            // Full-text search for documents
            r#"
            CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
                id UNINDEXED,
                filename,
                text_content,
                content='local_documents',
                content_rowid='rowid'
            )
            "#,
            
            // Triggers to keep FTS in sync
            r#"
            CREATE TRIGGER IF NOT EXISTS documents_fts_insert AFTER INSERT ON local_documents BEGIN
                INSERT INTO documents_fts(id, filename, text_content) 
                VALUES (new.id, new.filename, new.text_content);
            END
            "#,
            
            r#"
            CREATE TRIGGER IF NOT EXISTS documents_fts_update AFTER UPDATE ON local_documents BEGIN
                UPDATE documents_fts SET 
                    filename = new.filename,
                    text_content = new.text_content
                WHERE id = new.id;
            END
            "#,
            
            r#"
            CREATE TRIGGER IF NOT EXISTS documents_fts_delete AFTER DELETE ON local_documents BEGIN
                DELETE FROM documents_fts WHERE id = old.id;
            END
            "#,
        ];
        
        for migration in migrations {
            conn.execute(migration, ()).await
                .map_err(|e| AlemError::DatabaseError(format!("Migration failed: {}", e)))?;
        }
        
        Ok(())
    }
    
    pub async fn create_document(&self, document: &Document) -> Result<(), AlemError> {
        let conn = self.conn.as_ref()
            .ok_or_else(|| AlemError::DatabaseError("Database not initialized".to_string()))?;
        
        let metadata_json = serde_json::to_string(&document.metadata)
            .map_err(|e| AlemError::SerializationError(format!("Failed to serialize metadata: {}", e)))?;
        
        let tags_json = serde_json::to_string(&document.tags)
            .map_err(|e| AlemError::SerializationError(format!("Failed to serialize tags: {}", e)))?;
        
        let query = r#"
            INSERT INTO local_documents (
                id, user_id, tenant_id, filename, content_type, file_size, content_hash,
                local_path, is_cached_locally, local_version, server_version, is_synced,
                text_content, metadata, tags, status, needs_upload, needs_download,
                created_at, updated_at
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20
            )
        "#;
        
        conn.execute(query, (
            &document.id,
            &document.user_id,
            &document.tenant_id,
            &document.filename,
            &document.content_type,
            document.file_size,
            &document.content_hash,
            &document.local_path,
            document.is_cached_locally,
            document.local_version,
            document.server_version,
            document.is_synced,
            &document.text_content,
            &metadata_json,
            &tags_json,
            &document.status,
            document.needs_upload,
            document.needs_download,
            document.created_at.to_rfc3339(),
            document.updated_at.to_rfc3339(),
        )).await
        .map_err(|e| AlemError::DatabaseError(format!("Failed to create document: {}", e)))?;
        
        Ok(())
    }
    
    pub async fn get_documents(&self, user_id: &str) -> Result<Vec<Document>, AlemError> {
        let conn = self.conn.as_ref()
            .ok_or_else(|| AlemError::DatabaseError("Database not initialized".to_string()))?;
        
        let query = r#"
            SELECT id, user_id, tenant_id, filename, content_type, file_size, content_hash,
                   local_path, is_cached_locally, local_version, server_version, is_synced,
                   last_synced_at, text_content, metadata, tags, status, sync_error,
                   needs_upload, needs_download, created_at, updated_at
            FROM local_documents 
            WHERE user_id = ?1 AND status != 'deleted'
            ORDER BY created_at DESC
        "#;
        
        let mut rows = conn.prepare(query).await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to prepare query: {}", e)))?
            .query((user_id,)).await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to execute query: {}", e)))?;
        
        let mut documents = Vec::new();
        
        while let Some(row) = rows.next().await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to fetch row: {}", e)))? {
            
            let document = self.row_to_document(row)?;
            documents.push(document);
        }
        
        Ok(documents)
    }
    
    pub async fn get_document(&self, document_id: &str) -> Result<Document, AlemError> {
        let conn = self.conn.as_ref()
            .ok_or_else(|| AlemError::DatabaseError("Database not initialized".to_string()))?;
        
        let query = r#"
            SELECT id, user_id, tenant_id, filename, content_type, file_size, content_hash,
                   local_path, is_cached_locally, local_version, server_version, is_synced,
                   last_synced_at, text_content, metadata, tags, status, sync_error,
                   needs_upload, needs_download, created_at, updated_at
            FROM local_documents 
            WHERE id = ?1
        "#;
        
        let mut rows = conn.prepare(query).await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to prepare query: {}", e)))?
            .query((document_id,)).await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to execute query: {}", e)))?;
        
        if let Some(row) = rows.next().await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to fetch row: {}", e)))? {
            self.row_to_document(row)
        } else {
            Err(AlemError::NotFound(format!("Document not found: {}", document_id)))
        }
    }
    
    pub async fn search_documents(&self, user_id: &str, query: &str) -> Result<Vec<Document>, AlemError> {
        let conn = self.conn.as_ref()
            .ok_or_else(|| AlemError::DatabaseError("Database not initialized".to_string()))?;
        
        let search_query = r#"
            SELECT d.id, d.user_id, d.tenant_id, d.filename, d.content_type, d.file_size, d.content_hash,
                   d.local_path, d.is_cached_locally, d.local_version, d.server_version, d.is_synced,
                   d.last_synced_at, d.text_content, d.metadata, d.tags, d.status, d.sync_error,
                   d.needs_upload, d.needs_download, d.created_at, d.updated_at
            FROM local_documents d
            JOIN documents_fts fts ON d.id = fts.id
            WHERE d.user_id = ?1 AND d.status != 'deleted' AND documents_fts MATCH ?2
            ORDER BY rank
        "#;
        
        let mut rows = conn.prepare(search_query).await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to prepare search query: {}", e)))?
            .query((user_id, query)).await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to execute search query: {}", e)))?;
        
        let mut documents = Vec::new();
        
        while let Some(row) = rows.next().await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to fetch search row: {}", e)))? {
            
            let document = self.row_to_document(row)?;
            documents.push(document);
        }
        
        Ok(documents)
    }
    
    pub async fn store_oauth_token(&self, user_id: &str, token: &str) -> Result<(), AlemError> {
        let conn = self.conn.as_ref()
            .ok_or_else(|| AlemError::DatabaseError("Database not initialized".to_string()))?;
        
        let query = r#"
            INSERT OR REPLACE INTO local_users (
                id, oauth_token, updated_at
            ) VALUES (?1, ?2, ?3)
        "#;
        
        conn.execute(query, (
            user_id,
            token,
            chrono::Utc::now().to_rfc3339(),
        )).await
        .map_err(|e| AlemError::DatabaseError(format!("Failed to store OAuth token: {}", e)))?;
        
        Ok(())
    }
    
    pub async fn get_oauth_token(&self, user_id: &str) -> Result<Option<String>, AlemError> {
        let conn = self.conn.as_ref()
            .ok_or_else(|| AlemError::DatabaseError("Database not initialized".to_string()))?;
        
        let query = "SELECT oauth_token FROM local_users WHERE id = ?1";
        
        let mut rows = conn.prepare(query).await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to prepare token query: {}", e)))?
            .query((user_id,)).await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to execute token query: {}", e)))?;
        
        if let Some(row) = rows.next().await
            .map_err(|e| AlemError::DatabaseError(format!("Failed to fetch token row: {}", e)))? {
            let token: Option<String> = row.get(0)
                .map_err(|e| AlemError::DatabaseError(format!("Failed to get token value: {}", e)))?;
            Ok(token)
        } else {
            Ok(None)
        }
    }
    
    fn row_to_document(&self, row: libsql::Row) -> Result<Document, AlemError> {
        let metadata_json: String = row.get(14)
            .map_err(|e| AlemError::DatabaseError(format!("Failed to get metadata: {}", e)))?;
        let metadata: HashMap<String, String> = serde_json::from_str(&metadata_json)
            .map_err(|e| AlemError::SerializationError(format!("Failed to deserialize metadata: {}", e)))?;
        
        let tags_json: String = row.get(15)
            .map_err(|e| AlemError::DatabaseError(format!("Failed to get tags: {}", e)))?;
        let tags: Vec<String> = serde_json::from_str(&tags_json)
            .map_err(|e| AlemError::SerializationError(format!("Failed to deserialize tags: {}", e)))?;
        
        let created_at_str: String = row.get(20)
            .map_err(|e| AlemError::DatabaseError(format!("Failed to get created_at: {}", e)))?;
        let created_at = chrono::DateTime::parse_from_rfc3339(&created_at_str)
            .map_err(|e| AlemError::SerializationError(format!("Failed to parse created_at: {}", e)))?
            .with_timezone(&chrono::Utc);
        
        let updated_at_str: String = row.get(21)
            .map_err(|e| AlemError::DatabaseError(format!("Failed to get updated_at: {}", e)))?;
        let updated_at = chrono::DateTime::parse_from_rfc3339(&updated_at_str)
            .map_err(|e| AlemError::SerializationError(format!("Failed to parse updated_at: {}", e)))?
            .with_timezone(&chrono::Utc);
        
        Ok(Document {
            id: row.get(0).map_err(|e| AlemError::DatabaseError(format!("Failed to get id: {}", e)))?,
            user_id: row.get(1).map_err(|e| AlemError::DatabaseError(format!("Failed to get user_id: {}", e)))?,
            tenant_id: row.get(2).map_err(|e| AlemError::DatabaseError(format!("Failed to get tenant_id: {}", e)))?,
            filename: row.get(3).map_err(|e| AlemError::DatabaseError(format!("Failed to get filename: {}", e)))?,
            content_type: row.get(4).map_err(|e| AlemError::DatabaseError(format!("Failed to get content_type: {}", e)))?,
            file_size: row.get(5).map_err(|e| AlemError::DatabaseError(format!("Failed to get file_size: {}", e)))?,
            content_hash: row.get(6).map_err(|e| AlemError::DatabaseError(format!("Failed to get content_hash: {}", e)))?,
            local_path: row.get(7).map_err(|e| AlemError::DatabaseError(format!("Failed to get local_path: {}", e)))?,
            is_cached_locally: row.get(8).map_err(|e| AlemError::DatabaseError(format!("Failed to get is_cached_locally: {}", e)))?,
            local_version: row.get(9).map_err(|e| AlemError::DatabaseError(format!("Failed to get local_version: {}", e)))?,
            server_version: row.get(10).map_err(|e| AlemError::DatabaseError(format!("Failed to get server_version: {}", e)))?,
            is_synced: row.get(11).map_err(|e| AlemError::DatabaseError(format!("Failed to get is_synced: {}", e)))?,
            text_content: row.get(13).map_err(|e| AlemError::DatabaseError(format!("Failed to get text_content: {}", e)))?,
            metadata,
            tags,
            status: row.get(16).map_err(|e| AlemError::DatabaseError(format!("Failed to get status: {}", e)))?,
            needs_upload: row.get(18).map_err(|e| AlemError::DatabaseError(format!("Failed to get needs_upload: {}", e)))?,
            needs_download: row.get(19).map_err(|e| AlemError::DatabaseError(format!("Failed to get needs_download: {}", e)))?,
            created_at,
            updated_at,
        })
    }
}
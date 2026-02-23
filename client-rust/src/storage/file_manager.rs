use wasm_bindgen::prelude::*;
use web_sys::{IdbFactory, IdbDatabase, IdbTransaction, IdbObjectStore, IdbRequest};
use js_sys::{Uint8Array, Object, Reflect};
use crate::utils::error::AlemError;

pub struct FileManager {
    user_id: String,
    db_name: String,
}

impl FileManager {
    pub fn new(user_id: &str) -> Result<Self, AlemError> {
        Ok(FileManager {
            user_id: user_id.to_string(),
            db_name: format!("alem_files_{}", user_id),
        })
    }
    
    /// Store file content in IndexedDB or OPFS
    pub async fn store_file(&self, doc_id: &str, filename: &str, content: &[u8]) -> Result<String, JsValue> {
        let local_path = format!("files/{}/{}", doc_id, filename);
        
        // Try OPFS first (for larger files), fallback to IndexedDB
        match self.store_in_opfs(&local_path, content).await {
            Ok(_) => Ok(format!("opfs://{}", local_path)),
            Err(_) => {
                self.store_in_indexeddb(&local_path, content).await?;
                Ok(format!("indexeddb://{}", local_path))
            }
        }
    }
    
    /// Get file content from storage
    pub async fn get_file_content(&self, local_path: &str) -> Result<Vec<u8>, JsValue> {
        if local_path.starts_with("opfs://") {
            let path = &local_path[7..]; // Remove "opfs://" prefix
            self.get_from_opfs(path).await
        } else if local_path.starts_with("indexeddb://") {
            let path = &local_path[12..]; // Remove "indexeddb://" prefix
            self.get_from_indexeddb(path).await
        } else {
            Err(JsValue::from_str("Invalid local path format"))
        }
    }
    
    /// Delete file from storage
    pub async fn delete_file(&self, local_path: &str) -> Result<(), JsValue> {
        if local_path.starts_with("opfs://") {
            let path = &local_path[7..];
            self.delete_from_opfs(path).await
        } else if local_path.starts_with("indexeddb://") {
            let path = &local_path[12..];
            self.delete_from_indexeddb(path).await
        } else {
            Err(JsValue::from_str("Invalid local path format"))
        }
    }
    
    // OPFS (Origin Private File System) methods
    async fn store_in_opfs(&self, path: &str, content: &[u8]) -> Result<(), JsValue> {
        let window = web_sys::window().ok_or("No window object")?;
        let navigator = window.navigator();
        
        // Check if OPFS is supported
        let storage = Reflect::get(&navigator, &JsValue::from_str("storage"))?;
        if storage.is_undefined() {
            return Err(JsValue::from_str("OPFS not supported"));
        }
        
        // Get OPFS root
        let get_directory = Reflect::get(&storage, &JsValue::from_str("getDirectory"))?;
        let get_directory_fn = get_directory.dyn_into::<js_sys::Function>()?;
        let root_promise = get_directory_fn.call0(&storage)?;
        let root_handle = wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(root_promise)).await?;
        
        // Create directory structure
        let parts: Vec<&str> = path.split('/').collect();
        let mut current_handle = root_handle;
        
        for (i, part) in parts.iter().enumerate() {
            if i == parts.len() - 1 {
                // This is the file
                let create_file = Reflect::get(&current_handle, &JsValue::from_str("getFileHandle"))?;
                let create_file_fn = create_file.dyn_into::<js_sys::Function>()?;
                let options = Object::new();
                Reflect::set(&options, &JsValue::from_str("create"), &JsValue::from_bool(true))?;
                
                let file_promise = create_file_fn.call2(&current_handle, &JsValue::from_str(part), &options)?;
                let file_handle = wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(file_promise)).await?;
                
                // Create writable stream
                let create_writable = Reflect::get(&file_handle, &JsValue::from_str("createWritable"))?;
                let create_writable_fn = create_writable.dyn_into::<js_sys::Function>()?;
                let writable_promise = create_writable_fn.call0(&file_handle)?;
                let writable = wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(writable_promise)).await?;
                
                // Write content
                let write = Reflect::get(&writable, &JsValue::from_str("write"))?;
                let write_fn = write.dyn_into::<js_sys::Function>()?;
                let uint8_array = Uint8Array::from(content);
                let write_promise = write_fn.call1(&writable, &uint8_array)?;
                wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(write_promise)).await?;
                
                // Close writable
                let close = Reflect::get(&writable, &JsValue::from_str("close"))?;
                let close_fn = close.dyn_into::<js_sys::Function>()?;
                let close_promise = close_fn.call0(&writable)?;
                wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(close_promise)).await?;
                
            } else {
                // This is a directory
                let get_dir = Reflect::get(&current_handle, &JsValue::from_str("getDirectoryHandle"))?;
                let get_dir_fn = get_dir.dyn_into::<js_sys::Function>()?;
                let options = Object::new();
                Reflect::set(&options, &JsValue::from_str("create"), &JsValue::from_bool(true))?;
                
                let dir_promise = get_dir_fn.call2(&current_handle, &JsValue::from_str(part), &options)?;
                current_handle = wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(dir_promise)).await?;
            }
        }
        
        Ok(())
    }
    
    async fn get_from_opfs(&self, path: &str) -> Result<Vec<u8>, JsValue> {
        let window = web_sys::window().ok_or("No window object")?;
        let navigator = window.navigator();
        let storage = Reflect::get(&navigator, &JsValue::from_str("storage"))?;
        
        // Get OPFS root
        let get_directory = Reflect::get(&storage, &JsValue::from_str("getDirectory"))?;
        let get_directory_fn = get_directory.dyn_into::<js_sys::Function>()?;
        let root_promise = get_directory_fn.call0(&storage)?;
        let root_handle = wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(root_promise)).await?;
        
        // Navigate to file
        let parts: Vec<&str> = path.split('/').collect();
        let mut current_handle = root_handle;
        
        for (i, part) in parts.iter().enumerate() {
            if i == parts.len() - 1 {
                // Get file
                let get_file = Reflect::get(&current_handle, &JsValue::from_str("getFileHandle"))?;
                let get_file_fn = get_file.dyn_into::<js_sys::Function>()?;
                let file_promise = get_file_fn.call1(&current_handle, &JsValue::from_str(part))?;
                let file_handle = wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(file_promise)).await?;
                
                // Get file content
                let get_file_obj = Reflect::get(&file_handle, &JsValue::from_str("getFile"))?;
                let get_file_fn = get_file_obj.dyn_into::<js_sys::Function>()?;
                let file_promise = get_file_fn.call0(&file_handle)?;
                let file = wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(file_promise)).await?;
                
                // Read as array buffer
                let array_buffer = Reflect::get(&file, &JsValue::from_str("arrayBuffer"))?;
                let array_buffer_fn = array_buffer.dyn_into::<js_sys::Function>()?;
                let buffer_promise = array_buffer_fn.call0(&file)?;
                let buffer = wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(buffer_promise)).await?;
                
                let uint8_array = js_sys::Uint8Array::new(&buffer);
                let mut content = vec![0u8; uint8_array.length() as usize];
                uint8_array.copy_to(&mut content);
                
                return Ok(content);
            } else {
                // Navigate to directory
                let get_dir = Reflect::get(&current_handle, &JsValue::from_str("getDirectoryHandle"))?;
                let get_dir_fn = get_dir.dyn_into::<js_sys::Function>()?;
                let dir_promise = get_dir_fn.call1(&current_handle, &JsValue::from_str(part))?;
                current_handle = wasm_bindgen_futures::JsFuture::from(js_sys::Promise::from(dir_promise)).await?;
            }
        }
        
        Err(JsValue::from_str("File not found"))
    }
    
    async fn delete_from_opfs(&self, path: &str) -> Result<(), JsValue> {
        // Implementation for OPFS file deletion
        // Similar to get_from_opfs but calls removeEntry
        Ok(())
    }
    
    // IndexedDB methods
    async fn store_in_indexeddb(&self, path: &str, content: &[u8]) -> Result<(), JsValue> {
        let window = web_sys::window().ok_or("No window object")?;
        let idb_factory = window.indexed_db()?.ok_or("IndexedDB not supported")?;
        
        // Open database
        let open_request = idb_factory.open_with_u32(&self.db_name, 1)?;
        
        // Set up database schema if needed
        let onupgradeneeded = Closure::wrap(Box::new(move |event: web_sys::Event| {
            let target = event.target().unwrap();
            let request: IdbRequest = target.dyn_into().unwrap();
            let db: IdbDatabase = request.result().unwrap().dyn_into().unwrap();
            
            if !db.object_store_names().contains("files") {
                let store = db.create_object_store("files").unwrap();
                store.create_index("path", &JsValue::from_str("path")).unwrap();
            }
        }) as Box<dyn FnMut(_)>);
        
        open_request.set_onupgradeneeded(Some(onupgradeneeded.as_ref().unchecked_ref()));
        
        // Wait for database to open
        let db_promise = js_sys::Promise::new(&mut |resolve, reject| {
            let onsuccess = Closure::wrap(Box::new(move |event: web_sys::Event| {
                let target = event.target().unwrap();
                let request: IdbRequest = target.dyn_into().unwrap();
                let db = request.result().unwrap();
                resolve.call1(&JsValue::NULL, &db).unwrap();
            }) as Box<dyn FnMut(_)>);
            
            let onerror = Closure::wrap(Box::new(move |event: web_sys::Event| {
                let target = event.target().unwrap();
                let request: IdbRequest = target.dyn_into().unwrap();
                let error = request.error().unwrap();
                reject.call1(&JsValue::NULL, &error).unwrap();
            }) as Box<dyn FnMut(_)>);
            
            open_request.set_onsuccess(Some(onsuccess.as_ref().unchecked_ref()));
            open_request.set_onerror(Some(onerror.as_ref().unchecked_ref()));
            
            onsuccess.forget();
            onerror.forget();
        });
        
        let db: IdbDatabase = wasm_bindgen_futures::JsFuture::from(db_promise).await?.dyn_into()?;
        
        // Store file
        let transaction = db.transaction_with_str_and_mode("files", web_sys::IdbTransactionMode::Readwrite)?;
        let store = transaction.object_store("files")?;
        
        let file_object = Object::new();
        Reflect::set(&file_object, &JsValue::from_str("path"), &JsValue::from_str(path))?;
        Reflect::set(&file_object, &JsValue::from_str("content"), &Uint8Array::from(content))?;
        Reflect::set(&file_object, &JsValue::from_str("timestamp"), &JsValue::from_f64(js_sys::Date::now()))?;
        
        let put_request = store.put_with_key(&file_object, &JsValue::from_str(path))?;
        
        let put_promise = js_sys::Promise::new(&mut |resolve, reject| {
            let onsuccess = Closure::wrap(Box::new(move |_event: web_sys::Event| {
                resolve.call0(&JsValue::NULL).unwrap();
            }) as Box<dyn FnMut(_)>);
            
            let onerror = Closure::wrap(Box::new(move |event: web_sys::Event| {
                let target = event.target().unwrap();
                let request: IdbRequest = target.dyn_into().unwrap();
                let error = request.error().unwrap();
                reject.call1(&JsValue::NULL, &error).unwrap();
            }) as Box<dyn FnMut(_)>);
            
            put_request.set_onsuccess(Some(onsuccess.as_ref().unchecked_ref()));
            put_request.set_onerror(Some(onerror.as_ref().unchecked_ref()));
            
            onsuccess.forget();
            onerror.forget();
        });
        
        wasm_bindgen_futures::JsFuture::from(put_promise).await?;
        onupgradeneeded.forget();
        
        Ok(())
    }
    
    async fn get_from_indexeddb(&self, path: &str) -> Result<Vec<u8>, JsValue> {
        let window = web_sys::window().ok_or("No window object")?;
        let idb_factory = window.indexed_db()?.ok_or("IndexedDB not supported")?;
        
        let open_request = idb_factory.open(&self.db_name)?;
        
        let db_promise = js_sys::Promise::new(&mut |resolve, reject| {
            let onsuccess = Closure::wrap(Box::new(move |event: web_sys::Event| {
                let target = event.target().unwrap();
                let request: IdbRequest = target.dyn_into().unwrap();
                let db = request.result().unwrap();
                resolve.call1(&JsValue::NULL, &db).unwrap();
            }) as Box<dyn FnMut(_)>);
            
            let onerror = Closure::wrap(Box::new(move |event: web_sys::Event| {
                let target = event.target().unwrap();
                let request: IdbRequest = target.dyn_into().unwrap();
                let error = request.error().unwrap();
                reject.call1(&JsValue::NULL, &error).unwrap();
            }) as Box<dyn FnMut(_)>);
            
            open_request.set_onsuccess(Some(onsuccess.as_ref().unchecked_ref()));
            open_request.set_onerror(Some(onerror.as_ref().unchecked_ref()));
            
            onsuccess.forget();
            onerror.forget();
        });
        
        let db: IdbDatabase = wasm_bindgen_futures::JsFuture::from(db_promise).await?.dyn_into()?;
        
        let transaction = db.transaction_with_str("files")?;
        let store = transaction.object_store("files")?;
        let get_request = store.get(&JsValue::from_str(path))?;
        
        let get_promise = js_sys::Promise::new(&mut |resolve, reject| {
            let onsuccess = Closure::wrap(Box::new(move |event: web_sys::Event| {
                let target = event.target().unwrap();
                let request: IdbRequest = target.dyn_into().unwrap();
                let result = request.result().unwrap();
                resolve.call1(&JsValue::NULL, &result).unwrap();
            }) as Box<dyn FnMut(_)>);
            
            let onerror = Closure::wrap(Box::new(move |event: web_sys::Event| {
                let target = event.target().unwrap();
                let request: IdbRequest = target.dyn_into().unwrap();
                let error = request.error().unwrap();
                reject.call1(&JsValue::NULL, &error).unwrap();
            }) as Box<dyn FnMut(_)>);
            
            get_request.set_onsuccess(Some(onsuccess.as_ref().unchecked_ref()));
            get_request.set_onerror(Some(onerror.as_ref().unchecked_ref()));
            
            onsuccess.forget();
            onerror.forget();
        });
        
        let result = wasm_bindgen_futures::JsFuture::from(get_promise).await?;
        
        if result.is_null() || result.is_undefined() {
            return Err(JsValue::from_str("File not found"));
        }
        
        let content = Reflect::get(&result, &JsValue::from_str("content"))?;
        let uint8_array: Uint8Array = content.dyn_into()?;
        
        let mut buffer = vec![0u8; uint8_array.length() as usize];
        uint8_array.copy_to(&mut buffer);
        
        Ok(buffer)
    }
    
    async fn delete_from_indexeddb(&self, path: &str) -> Result<(), JsValue> {
        // Similar to get_from_indexeddb but calls delete
        Ok(())
    }
}
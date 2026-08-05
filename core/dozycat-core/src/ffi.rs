//! UniFFI 出口 — iOS(Swift) 用的接口面。
//!
//! 纯包装：类型换成 FFI 友好的 Record/Enum，`LoroStore` 包进 Mutex。
//! 生成绑定：`apps/ios/scripts/build-core.sh`。

use std::sync::Mutex;

use crate::{Category, CoreError, EnergyEvent, LoroStore, Memory};

#[derive(uniffi::Enum, Clone, Copy)]
pub enum FfiCategory {
    Happy,
    Body,
    People,
}

impl From<FfiCategory> for Category {
    fn from(c: FfiCategory) -> Self {
        match c {
            FfiCategory::Happy => Category::Happy,
            FfiCategory::Body => Category::Body,
            FfiCategory::People => Category::People,
        }
    }
}

impl From<Category> for FfiCategory {
    fn from(c: Category) -> Self {
        match c {
            Category::Happy => FfiCategory::Happy,
            Category::Body => FfiCategory::Body,
            Category::People => FfiCategory::People,
        }
    }
}

#[derive(uniffi::Record)]
pub struct FfiMemory {
    pub id: String,
    pub at_ms: i64,
    pub text: String,
    pub note: Option<String>,
    pub categories: Vec<FfiCategory>,
}

impl From<Memory> for FfiMemory {
    fn from(m: Memory) -> Self {
        FfiMemory {
            id: m.id,
            at_ms: m.at_ms,
            text: m.text,
            note: m.note,
            categories: m.categories.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record)]
pub struct FfiEnergy {
    pub at_ms: i64,
    pub device: String,
    pub phys: f64,
    pub mind: f64,
    pub kind: String,
}

#[derive(Debug, uniffi::Error)]
pub enum FfiError {
    Storage { msg: String },
    Crdt { msg: String },
}

impl std::fmt::Display for FfiError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FfiError::Storage { msg } => write!(f, "storage: {msg}"),
            FfiError::Crdt { msg } => write!(f, "crdt: {msg}"),
        }
    }
}

impl std::error::Error for FfiError {}

impl From<CoreError> for FfiError {
    fn from(e: CoreError) -> Self {
        match e {
            CoreError::Storage(msg) => FfiError::Storage { msg },
            CoreError::Crdt(msg) => FfiError::Crdt { msg },
        }
    }
}

/// iOS 侧的记忆库句柄（线程安全）。
#[derive(uniffi::Object)]
pub struct DozyStore {
    inner: Mutex<LoroStore>,
}

#[uniffi::export]
impl DozyStore {
    /// 打开（不存在则创建）store 文件。
    #[uniffi::constructor]
    pub fn open(path: String) -> Result<std::sync::Arc<Self>, FfiError> {
        let store = LoroStore::open(std::path::Path::new(&path))?;
        Ok(std::sync::Arc::new(Self { inner: Mutex::new(store) }))
    }

    pub fn add(
        &self,
        id: String,
        at_ms: i64,
        text: String,
        note: Option<String>,
        categories: Vec<FfiCategory>,
    ) -> Result<(), FfiError> {
        let memory = Memory {
            id,
            at_ms,
            text,
            note,
            categories: categories.into_iter().map(Into::into).collect(),
            tombstone: false,
        };
        Ok(self.lock().add(&memory)?)
    }

    pub fn edit(&self, id: String, text: String, note: Option<String>) -> Result<(), FfiError> {
        Ok(self.lock().edit(&id, &text, note.as_deref())?)
    }

    pub fn remove(&self, id: String) -> Result<(), FfiError> {
        Ok(self.lock().remove(&id)?)
    }

    pub fn timeline(&self, limit: u32) -> Vec<FfiMemory> {
        self.lock().timeline(limit as usize).into_iter().map(Into::into).collect()
    }

    pub fn search(&self, query: String) -> Vec<FfiMemory> {
        self.lock().search(&query).into_iter().map(Into::into).collect()
    }

    pub fn record_energy(&self, event: FfiEnergy) -> Result<(), FfiError> {
        Ok(self.lock().record_energy(&EnergyEvent {
            at_ms: event.at_ms,
            device: event.device,
            phys: event.phys,
            mind: event.mind,
            kind: event.kind,
        })?)
    }

    pub fn latest_energy(&self) -> Option<FfiEnergy> {
        self.lock().latest_energy().map(|e| FfiEnergy {
            at_ms: e.at_ms,
            device: e.device,
            phys: e.phys,
            mind: e.mind,
            kind: e.kind,
        })
    }

    pub fn version(&self) -> Vec<u8> {
        self.lock().version()
    }

    pub fn export_updates(&self, since_version: Vec<u8>) -> Result<Vec<u8>, FfiError> {
        Ok(self.lock().export_updates(&since_version)?)
    }

    pub fn import_updates(&self, updates: Vec<u8>) -> Result<(), FfiError> {
        Ok(self.lock().import_updates(&updates)?)
    }
}

impl DozyStore {
    fn lock(&self) -> std::sync::MutexGuard<'_, LoroStore> {
        self.inner.lock().unwrap_or_else(|p| p.into_inner())
    }
}

//! dozycat-core — 记忆与能量的共享内核（iOS 经 UniFFI，桌宠直接 path-dep）。
//!
//! 架构：docs/MEMORY-SYNC.md。
//! - CRDT 文档（Loro）：`memories` map（id → 条目 map）、`ledger` list（能量事件）
//! - SQLite 持久化：snapshot + 每设备固定 PeerID（版本向量纪律）
//! - `SyncTransport`：只搬密文的信箱（v1 = CKSyncEngine，见文档）

mod ffi;
pub use ffi::*;

uniffi::setup_scaffolding!();

use std::path::Path;

use loro::{ExportMode, LoroDoc, LoroMap, LoroValue, ValueOrContainer};
use rusqlite::Connection;

// ---------------------------------------------------------------------------
// 类型
// ---------------------------------------------------------------------------

/// 一条记忆。对应设计稿「记忆」页的条目与 iOS `Memory`。
#[derive(Debug, Clone, PartialEq)]
pub struct Memory {
    /// 稳定 id（调用方生成，建议 uuid v7）
    pub id: String,
    /// 记录时间，Unix 毫秒
    pub at_ms: i64,
    pub text: String,
    /// 懒猫的情绪注记，如「松了口气」「很累 · 那几天我盯紧一点」
    pub note: Option<String>,
    pub categories: Vec<Category>,
    /// 软删除（CRDT 里删除是墓碑；物理真删靠 shallow snapshot 压缩）
    pub tombstone: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Category {
    Happy,
    Body,
    People,
}

impl Category {
    fn bit(self) -> i64 {
        match self {
            Category::Happy => 1,
            Category::Body => 2,
            Category::People => 4,
        }
    }

    fn from_bits(bits: i64) -> Vec<Category> {
        [Category::Happy, Category::Body, Category::People]
            .into_iter()
            .filter(|c| bits & c.bit() != 0)
            .collect()
    }

    fn to_bits(cats: &[Category]) -> i64 {
        cats.iter().fold(0, |acc, c| acc | c.bit())
    }
}

/// 疲劳/补血事件（dozycat-sense 的语义输出落进同一本账，跨端同步）。
#[derive(Debug, Clone, PartialEq)]
pub struct EnergyEvent {
    pub at_ms: i64,
    pub device: String,
    pub phys: f64,
    pub mind: f64,
    /// "minute" | "nudge:<kind>" | "sleep-reset" …
    pub kind: String,
}

#[derive(Debug)]
pub enum CoreError {
    Storage(String),
    Crdt(String),
}

impl std::fmt::Display for CoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CoreError::Storage(e) => write!(f, "storage: {e}"),
            CoreError::Crdt(e) => write!(f, "crdt: {e}"),
        }
    }
}

impl std::error::Error for CoreError {}

impl From<rusqlite::Error> for CoreError {
    fn from(e: rusqlite::Error) -> Self {
        CoreError::Storage(e.to_string())
    }
}

impl From<loro::LoroError> for CoreError {
    fn from(e: loro::LoroError) -> Self {
        CoreError::Crdt(e.to_string())
    }
}

/// 同步传输：一个只会搬密文的信箱。v1 = CKSyncEngine（CloudKit 私有库），
/// 之后可加自托管 relay。加密在传输之前完成，传输层永远见不到明文。
pub trait SyncTransport {
    fn push(&mut self, ciphertext: Vec<u8>) -> Result<(), SyncError>;
    fn pull(&mut self, cursor: Option<String>) -> Result<PullPage, SyncError>;
}

pub struct PullPage {
    pub blobs: Vec<Vec<u8>>,
    pub next_cursor: Option<String>,
}

#[derive(Debug)]
pub enum SyncError {
    Offline,
    Auth(String),
    Transport(String),
}

// ---------------------------------------------------------------------------
// LoroStore
// ---------------------------------------------------------------------------

/// Loro doc + SQLite 持久化的记忆库。
///
/// 每个 store 文件绑定一个固定 PeerID（首次打开时生成并入库），
/// 同一文件绝不并行打开两份——这是版本向量不膨胀的纪律。
pub struct LoroStore {
    doc: LoroDoc,
    conn: Connection,
}

impl LoroStore {
    /// 打开（不存在则创建）。`path` 是 SQLite 文件路径；`:memory:` 仅测试用。
    pub fn open(path: &Path) -> Result<Self, CoreError> {
        let conn = Connection::open(path)?;
        Self::with_conn(conn)
    }

    pub fn open_in_memory() -> Result<Self, CoreError> {
        Self::with_conn(Connection::open_in_memory()?)
    }

    fn with_conn(conn: Connection) -> Result<Self, CoreError> {
        // 单写者纪律的强制：EXCLUSIVE locking + 立即拿写锁。
        // 同一 store 文件被第二个进程打开时，这里直接报错（而不是两个进程
        // 复用同一 PeerID 并发写——那会破坏 CRDT 的 (peer, counter) 唯一性）。
        conn.busy_timeout(std::time::Duration::ZERO)
            .map_err(|e| CoreError::Storage(e.to_string()))?;
        conn.pragma_update(None, "locking_mode", "exclusive")
            .map_err(|e| CoreError::Storage(e.to_string()))?;
        conn.execute_batch(
            "BEGIN EXCLUSIVE;
             CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value BLOB NOT NULL);
             COMMIT;",
        )
        .map_err(|e| CoreError::Storage(format!("store already in use elsewhere? {e}")))?;
        let doc = LoroDoc::new();

        let snapshot: Option<Vec<u8>> = conn
            .query_row("SELECT value FROM meta WHERE key='snapshot'", [], |r| r.get(0))
            .ok();
        if let Some(bytes) = snapshot {
            doc.import(&bytes)?;
        }

        // 每设备固定 PeerID（docs/MEMORY-SYNC.md「密钥与身份纪律」）
        let peer: Option<Vec<u8>> = conn
            .query_row("SELECT value FROM meta WHERE key='peer_id'", [], |r| r.get(0))
            .ok();
        let peer_id = match peer {
            Some(bytes) if bytes.len() == 8 => u64::from_le_bytes(bytes.try_into().unwrap()),
            _ => {
                let id: u64 = random_u64();
                conn.execute(
                    "INSERT OR REPLACE INTO meta (key, value) VALUES ('peer_id', ?1)",
                    [id.to_le_bytes().to_vec()],
                )?;
                id
            }
        };
        doc.set_peer_id(peer_id)?;

        Ok(Self { doc, conn })
    }

    pub fn peer_id(&self) -> u64 {
        self.doc.peer_id()
    }

    fn persist(&self) -> Result<(), CoreError> {
        let snapshot = self
            .doc
            .export(ExportMode::Snapshot)
            .map_err(|e| CoreError::Crdt(e.to_string()))?;
        self.conn.execute(
            "INSERT OR REPLACE INTO meta (key, value) VALUES ('snapshot', ?1)",
            [snapshot],
        )?;
        Ok(())
    }

    fn memories_map(&self) -> LoroMap {
        self.doc.get_map("memories")
    }

    // ---- 记忆 ----

    pub fn add(&self, memory: &Memory) -> Result<(), CoreError> {
        let item = self
            .memories_map()
            .insert_container(&memory.id, LoroMap::new())?;
        item.insert("at_ms", memory.at_ms)?;
        item.insert("text", memory.text.as_str())?;
        if let Some(n) = &memory.note {
            item.insert("note", n.as_str())?;
        }
        item.insert("cats", Category::to_bits(&memory.categories))?;
        item.insert("tombstone", memory.tombstone)?;
        self.persist()
    }

    pub fn edit(&self, id: &str, text: &str, note: Option<&str>) -> Result<(), CoreError> {
        if let Some(item) = self.item(id) {
            item.insert("text", text)?;
            match note {
                Some(n) => item.insert("note", n)?,
                None => item.delete("note")?,
            }
            self.persist()?;
        }
        Ok(())
    }

    /// 打墓碑（物理真删靠 shallow snapshot 压缩，见文档）
    pub fn remove(&self, id: &str) -> Result<(), CoreError> {
        if let Some(item) = self.item(id) {
            item.insert("tombstone", true)?;
            self.persist()?;
        }
        Ok(())
    }

    /// 时间倒序（最新在前），过滤墓碑。
    pub fn timeline(&self, limit: usize) -> Vec<Memory> {
        let mut all = self.all_alive();
        all.sort_by_key(|m| std::cmp::Reverse(m.at_ms));
        all.truncate(limit);
        all
    }

    /// 朴素子串搜索（FTS5 投影是后续里程碑）。
    pub fn search(&self, query: &str) -> Vec<Memory> {
        let q = query.trim();
        if q.is_empty() {
            return self.timeline(usize::MAX);
        }
        let mut hits: Vec<Memory> = self
            .all_alive()
            .into_iter()
            .filter(|m| {
                m.text.contains(q) || m.note.as_deref().is_some_and(|n| n.contains(q))
            })
            .collect();
        hits.sort_by_key(|m| std::cmp::Reverse(m.at_ms));
        hits
    }

    fn item(&self, id: &str) -> Option<LoroMap> {
        match self.memories_map().get(id) {
            Some(ValueOrContainer::Container(c)) => c.into_map().ok(),
            _ => None,
        }
    }

    fn all_alive(&self) -> Vec<Memory> {
        let map = self.memories_map();
        let mut out = Vec::new();
        for id in map.keys() {
            if let Some(ValueOrContainer::Container(c)) = map.get(&id) {
                if let Ok(item) = c.into_map() {
                    if let Some(m) = read_memory(&id, &item) {
                        if !m.tombstone {
                            out.push(m);
                        }
                    }
                }
            }
        }
        out
    }

    // ---- 能量账本 ----

    pub fn record_energy(&self, event: &EnergyEvent) -> Result<(), CoreError> {
        let ledger = self.doc.get_list("ledger");
        let entries: Vec<(String, LoroValue)> = vec![
            ("at_ms".into(), LoroValue::from(event.at_ms)),
            ("device".into(), LoroValue::from(event.device.as_str())),
            ("phys".into(), LoroValue::from(event.phys)),
            ("mind".into(), LoroValue::from(event.mind)),
            ("kind".into(), LoroValue::from(event.kind.as_str())),
        ];
        ledger.push(LoroValue::Map(loro::LoroMapValue::from(entries)))?;
        self.persist()
    }

    /// 全账本里 at_ms 最大的一条（多设备合并后以时间为准）。
    pub fn latest_energy(&self) -> Option<EnergyEvent> {
        let ledger = self.doc.get_list("ledger");
        let mut best: Option<EnergyEvent> = None;
        for i in 0..ledger.len() {
            if let Some(ValueOrContainer::Value(LoroValue::Map(m))) = ledger.get(i) {
                if let Some(e) = read_energy(&m) {
                    if best.as_ref().is_none_or(|b| e.at_ms >= b.at_ms) {
                        best = Some(e);
                    }
                }
            }
        }
        best
    }

    // ---- 同步 ----

    /// 导出自 `since_version`（空 = 从头）以来的 update 块。
    /// 加密后交给 `SyncTransport`；对端 `import_updates` 合入。
    pub fn export_updates(&self, since_version: &[u8]) -> Result<Vec<u8>, CoreError> {
        let vv = if since_version.is_empty() {
            loro::VersionVector::new()
        } else {
            loro::VersionVector::decode(since_version)?
        };
        self.doc
            .export(ExportMode::updates(&vv))
            .map_err(|e| CoreError::Crdt(e.to_string()))
    }

    /// 当前版本向量（下次增量导出的起点）。
    pub fn version(&self) -> Vec<u8> {
        self.doc.oplog_vv().encode()
    }

    /// 合入远端 update——CRDT 保证任意顺序、重复导入都收敛。
    pub fn import_updates(&self, updates: &[u8]) -> Result<(), CoreError> {
        self.doc.import(updates)?;
        self.persist()
    }
}

fn read_memory(id: &str, item: &LoroMap) -> Option<Memory> {
    Some(Memory {
        id: id.to_string(),
        at_ms: get_i64(item, "at_ms")?,
        text: get_str(item, "text")?,
        note: get_str(item, "note"),
        categories: Category::from_bits(get_i64(item, "cats").unwrap_or(0)),
        tombstone: get_bool(item, "tombstone").unwrap_or(false),
    })
}

fn read_energy(m: &loro::LoroMapValue) -> Option<EnergyEvent> {
    let i64_of = |k: &str| match m.get(k) {
        Some(LoroValue::I64(v)) => Some(*v),
        _ => None,
    };
    let f64_of = |k: &str| match m.get(k) {
        Some(LoroValue::Double(v)) => Some(*v),
        _ => None,
    };
    let str_of = |k: &str| match m.get(k) {
        Some(LoroValue::String(s)) => Some(s.as_str().to_string()),
        _ => None,
    };
    Some(EnergyEvent {
        at_ms: i64_of("at_ms")?,
        device: str_of("device")?,
        phys: f64_of("phys")?,
        mind: f64_of("mind")?,
        kind: str_of("kind")?,
    })
}

fn get_str(map: &LoroMap, key: &str) -> Option<String> {
    match map.get(key) {
        Some(ValueOrContainer::Value(LoroValue::String(s))) => Some(s.to_string()),
        _ => None,
    }
}

fn get_i64(map: &LoroMap, key: &str) -> Option<i64> {
    match map.get(key) {
        Some(ValueOrContainer::Value(LoroValue::I64(v))) => Some(v),
        _ => None,
    }
}

fn get_bool(map: &LoroMap, key: &str) -> Option<bool> {
    match map.get(key) {
        Some(ValueOrContainer::Value(LoroValue::Bool(v))) => Some(v),
        _ => None,
    }
}

/// 不引入 rand 依赖的随机 u64（时间 + 地址熵哈希）。PeerID 只需避免碰撞，
/// 不承担安全职责（见 docs/MEMORY-SYNC.md）。
fn random_u64() -> u64 {
    use std::collections::hash_map::RandomState;
    use std::hash::{BuildHasher, Hasher};
    let mut h = RandomState::new().build_hasher();
    h.write_u128(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos(),
    );
    h.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mem(id: &str, at_ms: i64, text: &str) -> Memory {
        Memory {
            id: id.into(),
            at_ms,
            text: text.into(),
            note: None,
            categories: vec![Category::People],
            tombstone: false,
        }
    }

    #[test]
    fn roundtrip_persistence() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("store.db");
        let peer;
        {
            let store = LoroStore::open(&path).unwrap();
            peer = store.peer_id();
            store.add(&mem("m1", 100, "有点怕见小林")).unwrap();
            store
                .add(&Memory { note: Some("松了口气".into()), ..mem("m2", 200, "聊开了") })
                .unwrap();
        }
        let store = LoroStore::open(&path).unwrap();
        assert_eq!(store.peer_id(), peer, "PeerID 必须每设备固定");
        let tl = store.timeline(10);
        assert_eq!(tl.len(), 2);
        assert_eq!(tl[0].id, "m2", "时间倒序");
        assert_eq!(tl[1].text, "有点怕见小林");
        assert_eq!(tl[0].note.as_deref(), Some("松了口气"));
    }

    #[test]
    fn tombstone_hides_and_survives_sync() {
        let a = LoroStore::open_in_memory().unwrap();
        a.add(&mem("m1", 1, "x")).unwrap();
        a.remove("m1").unwrap();
        assert!(a.timeline(10).is_empty());

        let b = LoroStore::open_in_memory().unwrap();
        b.import_updates(&a.export_updates(&[]).unwrap()).unwrap();
        assert!(b.timeline(10).is_empty(), "墓碑必须随同步传播");
    }

    #[test]
    fn two_replicas_converge() {
        let a = LoroStore::open_in_memory().unwrap();
        let b = LoroStore::open_in_memory().unwrap();

        a.add(&mem("a1", 10, "A 写的")).unwrap();
        b.add(&mem("b1", 20, "B 写的")).unwrap();
        b.record_energy(&EnergyEvent {
            at_ms: 99,
            device: "iphone".into(),
            phys: 45.0,
            mind: 72.0,
            kind: "minute".into(),
        })
        .unwrap();

        // 双向交换（任意顺序）
        let a_updates = a.export_updates(&[]).unwrap();
        let b_updates = b.export_updates(&[]).unwrap();
        a.import_updates(&b_updates).unwrap();
        b.import_updates(&a_updates).unwrap();

        let ta = a.timeline(10);
        let tb = b.timeline(10);
        assert_eq!(ta, tb, "双副本必须收敛");
        assert_eq!(ta.len(), 2);
        assert_eq!(a.latest_energy().unwrap().phys, 45.0);
    }

    #[test]
    fn concurrent_edit_converges_without_loss() {
        let a = LoroStore::open_in_memory().unwrap();
        a.add(&mem("m1", 1, "原文")).unwrap();
        let b = LoroStore::open_in_memory().unwrap();
        b.import_updates(&a.export_updates(&[]).unwrap()).unwrap();

        a.edit("m1", "A 的版本", Some("A 注记")).unwrap();
        b.edit("m1", "B 的版本", None).unwrap();

        let a_up = a.export_updates(&[]).unwrap();
        let b_up = b.export_updates(&[]).unwrap();
        a.import_updates(&b_up).unwrap();
        b.import_updates(&a_up).unwrap();

        let ma = &a.timeline(1)[0];
        let mb = &b.timeline(1)[0];
        assert_eq!(ma, mb, "并发编辑后两端一致");
        assert!(ma.text == "A 的版本" || ma.text == "B 的版本");
    }

    #[test]
    fn incremental_updates_since_version() {
        let a = LoroStore::open_in_memory().unwrap();
        a.add(&mem("m1", 1, "第一条")).unwrap();
        let v1 = a.version();
        a.add(&mem("m2", 2, "第二条")).unwrap();

        let b = LoroStore::open_in_memory().unwrap();
        b.import_updates(&a.export_updates(&[]).unwrap()).unwrap();

        let inc = a.export_updates(&v1).unwrap();
        let full = a.export_updates(&[]).unwrap();
        assert!(inc.len() < full.len(), "增量应显著小于全量");
        // 重复导入幂等
        b.import_updates(&inc).unwrap();
        b.import_updates(&inc).unwrap();
        assert_eq!(b.timeline(10).len(), 2);
    }

    #[test]
    fn second_open_of_same_store_is_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("store.db");
        let first = LoroStore::open(&path).unwrap();
        first.add(&mem("m1", 1, "第一进程写入")).unwrap();

        // 单写者纪律：同一文件并行第二次打开必须失败（PeerID 不可并行复用）
        assert!(LoroStore::open(&path).is_err());

        drop(first);
        let reopened = LoroStore::open(&path).unwrap();
        assert_eq!(reopened.timeline(10).len(), 1, "关闭后可正常重开");
    }

    #[test]
    fn edit_clearing_absent_note_is_harmless() {
        let s = LoroStore::open_in_memory().unwrap();
        s.add(&mem("m1", 1, "原文")).unwrap();
        s.edit("m1", "新文", None).unwrap(); // 本来就没有 note，删除不应报错
        let m = &s.timeline(1)[0];
        assert_eq!(m.text, "新文");
        assert_eq!(m.note, None);
    }

    #[test]
    fn search_matches_text_and_note() {
        let s = LoroStore::open_in_memory().unwrap();
        s.add(&Memory { note: Some("周六提醒你买牛腩".into()), ..mem("m1", 1, "妈妈想吃番茄牛腩") })
            .unwrap();
        s.add(&mem("m2", 2, "散了一圈步")).unwrap();
        assert_eq!(s.search("牛腩").len(), 1);
        assert_eq!(s.search("提醒").len(), 1, "note 也要能搜到");
        assert_eq!(s.search("跑步").len(), 0);
    }
}

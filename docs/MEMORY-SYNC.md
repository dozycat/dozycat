# 记忆多端同步 — 设计决定

需求：iOS app、macOS 桌宠（Rust 进程）、未来可能的 Android/Web；离线优先；
「只存在你自己的设备里」是产品承诺（服务器只能见密文）；记忆是高频追加 +
偶尔编辑/删除，多端并发写必须无冲突合并；iOS 要过 App Store 审核；尽量零运维。

## 结论（SOTA 组合）

**共享 Rust 核心 `dozycat-core`，记忆库用 CRDT（[Loro](https://loro.dev)），
同步传输只搬运端到端加密的 update blob，v1 传输走 CloudKit 私有库。**

```text
┌────────── iOS app (Swift) ──────────┐   ┌───── macOS 桌宠 (Rust) ─────┐
│ SwiftUI ── UniFFI ──┐               │   │ pet/agent ──┐               │
│                 dozycat-core        │   │         dozycat-core        │
│           Loro doc + SQLite 持久化   │   │   （同一个 crate，同一套合并）│
└──────────────┬──────────────────────┘   └──────────────┬──────────────┘
               │  encrypt(update blob, device-shared key) │
               └────────────► CloudKit 私有库 ◄────────────┘
                    （CKSyncEngine，只见密文；未来可换自托管 relay）
```

### 为什么这是 SOTA 而不是「直接 CloudKit / 直接上服务器」

| 方案 | 淘汰原因 |
|---|---|
| SwiftData + CloudKit（纯 Apple 栈） | 合并语义是 last-writer-wins（字段级冲突丢数据）；Rust 桌宠接 CloudKit 原生表结构非常痛；永远绑死 Apple 生态 |
| cr-sqlite / Turso / PowerSync / Electric | 要么服务器可见明文（违背产品承诺），要么托管服务成为运维+信任负担；E2EE 要自己叠加 |
| Automerge | 与 Loro 同类；Loro 是 Rust 原生、性能更好、有 rich text/moveable list，且我们全栈 Rust 核心，绑定成本最低 |

选中方案的每一层都是当前局部最优：

- **local-first + CRDT**：每台设备是完整副本，离线可读写，合并数学上收敛
  （Ink & Switch 一系的公认方向）。记忆 = Loro map/list（条目、标签、情绪注记），
  编辑/删除天然收敛，无「同步冲突」这个概念。
- **一份 Rust 核心到处跑**：合并语义只实现一次。iOS 经 UniFFI 出 Swift 接口；
  桌宠直接 path-dep。未来 Android（JNI）/Web（wasm）零重写——Loro 本身支持 wasm。
- **传输只是「密文信箱」**：`SyncTransport` trait 只有
  `push(blobs)` / `pull(since) -> blobs`。v1 用 **CKSyncEngine**（Apple 官方
  增量同步引擎，免费、免运维、用户自己的 iCloud 配额）；桌宠侧经一个小 Swift
  helper（同 cat 仓库 `apps/paperboy/native/*.swift` 的做法）或 objc2 直调。
  blob 在设备侧用对称密钥加密（密钥放 iCloud Keychain，与 Apple 端到端加密
  一致的信任模型），CloudKit 只见密文 → 产品承诺成立。
- **可迁移**：换自托管 relay（一个 ~百行的 blob 信箱服务）不动核心一行代码。

## 数据模型（v1）

```text
LoroDoc
 ├─ memories: LoroMovableList<MemoryId>            // 时间线顺序
 ├─ memory:<id>: LoroMap { text, date, mood, kind, // 单条记忆
 │                          categories, tombstone }
 ├─ energy: LoroMap { phys, mind, updatedAt, device } // 最新能量快照（LWW 即可）
 └─ ledger: LoroList<EnergyEvent>                  // 疲劳/补血事件流（见 FATIGUE.md）
```

- 附件（语音、图片）不进 CRDT：内容寻址（BLAKE3）密文块，懒同步。
- 本地持久化：SQLite 一张 `loro_updates` 表 + 周期 snapshot 压缩；FTS5 索引
  从 doc 投影（搜索「上次牙疼是什么时候」）。

## 账户与多用户

Loro 没有账户概念（它只是合并引擎）；「谁的数据」在传输层之上解决：

```text
账户/登录（谁）      ← auth 层：Apple ID / 自建账号
   ↓ user_id
同步传输（搬运）     ← 每用户一个隔离的密文信箱
   ↓ blobs
Loro（怎么合并）     ← 每用户自己的 doc，只在 TA 自己的设备间合并
```

- **路线 A（v1）**：CloudKit 私有库 = 身份就是用户的 iCloud 账号，
  **不用建账户系统、可以没有登录界面**；用户之间物理隔离，开发者不可见。
- **路线 B（跨平台时）**：Sign in with Apple（App Store 规定：提供第三方登录
  就必须带它）+ 手机号/邮箱；relay 按 `user_id` 隔离信箱。核心层零改动。
- 产品定位是「它只负责你」：v1 不做用户间共享；若未来做（家人互看能量），
  只需 relay 加按-doc 授权，Loro 天然支持共享 doc 合并。

## 密钥与身份纪律

- **PeerID**：Loro 每副本一个随机 u64。纪律：**每设备固定一个 PeerID**
  （存在 core 的设备表里，绝不并行复用），避免每次启动随机导致版本向量膨胀。
  **强制手段**：store 打开即持有 SQLite EXCLUSIVE 锁——同一文件的第二个进程
  open 直接失败（调用方降级为无账本运行），杜绝并行复用同一 PeerID。
- **年度 shallow snapshot 压缩**：CRDT 历史只增不减 + 删除是墓碑。定期浅快照
  截断老历史，一举三得：控制体积、重置版本向量、**物理真删**
  （隐私要求的"真的删掉了"靠这个，不靠 CRDT 默认行为）。
- **恢复故事**：全部设备丢失时，数据 = iCloud 密文 + iCloud Keychain 里的
  数据密钥，恢复 Apple 账号即恢复一切。用户关闭 iCloud Keychain 的兜底：
  一次性**恢复码**（Signal/1Password 模式）。设备被盗：从 Keychain 撤设备 +
  轮换数据密钥，后续 update 重加密。

## 设置与 Key 的同步

- **API Key（机密）不进 CRDT**：走 **iCloud 钥匙串**（`kSecAttrSynchronizable`
  条目，Apple 端到端加密，零自建设施）。iOS ↔ macOS 共享同一条目需要两个
  target 挂同一个 keychain access group（`com.paperboytm.dozycat.shared`，
  签名时启用——project.yml 里已留注释；开发期未签名构建各存各的，代码零改动）。
- **provider / model / baseURL（非机密）**：进 core 的 `settings` map，
  随小传账本一起 CRDT 同步（里程碑，transport 落地即生效）。

## 威胁模型（谁挡什么）

| 威胁 | 谁挡 | 方案 |
|---|---|---|
| 落盘被读（设备丢失） | 本地加密 | iOS Data Protection + SQLite 应用级加密（密钥在本机 Keychain） |
| 传输/云端被看 | E2EE | update blob 出设备前 XChaCha20-Poly1305；CloudKit/relay 只见密文 |
| 服务器篡改/重放 | AEAD + CRDT | Poly1305 认证标签挡篡改；重放 update 对 CRDT 幂等无害 |
| 用户间越权 | 传输隔离 | CloudKit 私有库天然隔离；relay 按 auth token 隔离 |
| 「删除」没真删 | 浅快照 | 见上——压缩后墓碑前史物理消失 |

固有代价（主动选择）：E2EE 下服务器无法校验/修复数据，正确性全靠端上
Loro 的确定性合并——与产品承诺一致。

## 成本模型

Loro 是 MIT 开源库（跑在端上，无配额无账单）。有成本的只有传输层：
v1 CloudKit 私有库的存储记在**每个用户自己的 iCloud 免费配额**里
（记忆密文一年 MB 级），开发者边际成本为零，只付 $99/年开发者账号；
路线 B 的 relay 是"每用户几 MB 密文"级的最便宜负载。

## 里程碑

1. ✅ `core/dozycat-core`：Loro doc + SQLite 持久化、`MemoryStore` API
   （add/edit/tombstone/timeline/search/energy ledger/export/import）、
   固定 PeerID、双副本收敛测试
2. ✅ UniFFI 绑定 + XCFramework → iOS 用真存储替换 `AppModel` 的内存假数据
3. CKSyncEngine 传输（iOS 先行，桌宠经 Swift helper 复用同一容器）
4. 加密层（XChaCha20-Poly1305，密钥入 Keychain/iCloud Keychain + 恢复码）
5. 年度 shallow snapshot 压缩任务（体积/版本向量/真删）
6. 自托管 relay（可选，非 Apple 端需要时再做）

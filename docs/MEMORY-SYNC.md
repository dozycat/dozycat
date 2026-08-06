# 记忆多端同步 — 设计决定

需求摆在这里：iOS app、macOS 桌宠（一个 Rust 进程）、将来可能的 Android 和 Web；
离线优先；「只存在你自己的设备里」是写进产品的承诺，服务器只许见密文；记忆的
写法是高频追加加上偶尔的编辑删除，多端并发写必须无冲突地合并；iOS 要过审；
运维越少越好。

结论一句话：**共享一个 Rust 核心 `dozycat-core`，记忆库用 CRDT（[Loro](https://loro.dev)），
同步传输只搬运端到端加密的 update blob，v1 的传输走 CloudKit 私有库。**

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

## 为什么不是那几条更省事的路

纯 Apple 栈（SwiftData + CloudKit）试过说服自己：合并语义是 last-writer-wins，
字段级冲突就丢数据；让 Rust 桌宠去接 CloudKit 的原生表结构非常痛；而且从此绑死
Apple 生态。cr-sqlite、Turso、PowerSync、Electric 这一类，要么服务器看得见明文，
直接违背产品承诺，要么托管服务本身成了运维和信任的负担，端到端加密还得自己往上
叠。Automerge 和 Loro 同类，但 Loro 是 Rust 原生、性能更好、带 rich text 和
moveable list——我们全栈就是 Rust 核心，绑定成本最低。

选中的组合，每一层都有各自的道理。local-first 加 CRDT：每台设备是完整副本，
离线随便读写，合并在数学上收敛（Ink & Switch 一系的公认方向）；记忆表达成 Loro
的 map 和 list（条目、标签、情绪注记），编辑删除天然收敛，「同步冲突」这个概念
不存在。一份 Rust 核心到处跑：合并语义只实现一次，iOS 经 UniFFI 出 Swift 接口，
桌宠直接 path-dep，将来 Android 走 JNI、Web 走 wasm，零重写——Loro 本身支持
wasm。传输层只是一个密文信箱：`SyncTransport` trait 只有 `push(blobs)` 和
`pull(since) -> blobs` 两个方法；v1 用 CKSyncEngine，Apple 官方的增量同步引擎，
免费免运维，配额记在用户自己的 iCloud 上；桌宠侧过一个小 Swift helper（cat 仓库
`apps/paperboy/native/*.swift` 的做法）或 objc2 直调。blob 出设备前用对称密钥
加密，密钥放 iCloud Keychain，信任模型与 Apple 自家的端到端加密一致——CloudKit
只见密文，产品承诺成立。哪天要换自托管 relay，一个百来行的 blob 信箱服务，
核心一行不动。

## 数据模型（v1）

```text
LoroDoc
 ├─ memories: LoroMovableList<MemoryId>            // 时间线顺序
 ├─ memory:<id>: LoroMap { text, date, mood, kind, // 单条记忆
 │                          categories, tombstone }
 ├─ energy: LoroMap { phys, mind, updatedAt, device } // 最新能量快照（LWW 即可）
 └─ ledger: LoroList<EnergyEvent>                  // 疲劳/补血事件流（见 FATIGUE.md）
```

语音、图片这类附件不进 CRDT：内容寻址（BLAKE3）的密文块，懒同步。本地持久化是
SQLite 一张 `loro_updates` 表加周期性的 snapshot 压缩；FTS5 索引从 doc 投影出来，
「上次牙疼是什么时候」这类搜索走它。

## 账户与多用户

Loro 没有账户概念，它只是合并引擎；「这是谁的数据」在传输层之上解决——auth 层
管你是谁（Apple ID 或自建账号），传输层按 user_id 给每人一个隔离的密文信箱，
Loro 只在同一个人的设备之间合并同一份 doc。v1 走路线 A：CloudKit 私有库，身份
就是用户的 iCloud 账号，不用建账户系统，可以没有登录界面，用户之间物理隔离，
开发者不可见。要跨平台时走路线 B：Sign in with Apple（App Store 规定，提供第三方
登录就必须带它）加手机号邮箱，relay 按 user_id 隔离信箱，核心层零改动。产品定位
是「它只负责你」，v1 不做用户间共享；将来若做家人互看能量，relay 加按 doc 的授权
即可，Loro 天然支持共享 doc 的合并。

## 密钥与身份的纪律

PeerID：Loro 给每个副本一个随机 u64。纪律是每台设备固定一个，存在 core 的设备表
里，绝不并行复用——否则版本向量膨胀。强制手段很直接：store 打开即持有 SQLite
的 EXCLUSIVE 锁，同一文件的第二个进程 open 直接失败（调用方降级为无账本运行），
从根上杜绝两个进程共用一个 PeerID。

年度 shallow snapshot 压缩：CRDT 的历史只增不减，删除还是墓碑。定期打一个浅快照
截断老历史，一举三得——控制体积、重置版本向量、物理真删。隐私要求里那句
「真的删掉了」，靠的是这个，不靠 CRDT 的默认行为。

恢复的故事：全部设备丢失时，数据等于 iCloud 里的密文加 iCloud Keychain 里的数据
密钥，恢复 Apple 账号就恢复了一切。用户关掉 iCloud Keychain 的兜底是一次性恢复码
（Signal、1Password 的模式）。设备被盗：从 Keychain 撤掉那台设备，轮换数据密钥，
后续 update 重新加密。

## 设置与 Key 的同步

API Key 是机密，不进 CRDT，走 iCloud 钥匙串（`kSecAttrSynchronizable` 条目，
Apple 端到端加密，零自建设施）。iOS 和 macOS 共享同一条目需要两个 target 挂同
一个 keychain access group（`com.paperboytm.dozycat.shared`，签名时启用，
project.yml 里留了注释；开发期未签名的构建各存各的，代码零改动）。provider、
model、baseURL 不算机密，进 core 的 `settings` map，随小传账本一起 CRDT 同步
（transport 落地即生效）。

## 威胁模型：谁挡什么

设备丢了、落盘被读——本地加密挡：iOS Data Protection 加 SQLite 应用级加密，
密钥在本机 Keychain。传输和云端被看——端到端加密挡：update blob 出设备前过
XChaCha20-Poly1305，CloudKit 或 relay 只见密文。服务器篡改或重放——AEAD 加 CRDT
挡：Poly1305 的认证标签挡篡改，重放的 update 对 CRDT 幂等无害。用户间越权——
传输隔离挡：CloudKit 私有库天然隔离，relay 按 auth token 隔离。「删除」没真删
——浅快照挡：压缩之后墓碑连同前史物理消失。固有的代价是主动选的：端到端加密
之下服务器无法校验和修复数据，正确性全押在端上 Loro 的确定性合并——这与产品
承诺本来就是一回事。

## 成本

Loro 是 MIT 开源库，跑在端上，无配额无账单。有成本的只有传输层：v1 的 CloudKit
私有库把存储记在每个用户自己的 iCloud 免费配额里（记忆密文一年 MB 级），开发者
边际成本为零，只付每年 99 美元的开发者账号；路线 B 的 relay 是「每用户几 MB
密文」级的、最便宜的那种负载。

## 里程碑

`core/dozycat-core` 已经落地：Loro doc 加 SQLite 持久化，`MemoryStore` 的
add / edit / tombstone / timeline / search / energy ledger / export / import，
固定 PeerID，双副本收敛测试。UniFFI 绑定和 XCFramework 也已就位，iOS 用真存储
替换了 `AppModel` 的内存假数据。接下来依次是：CKSyncEngine 传输（iOS 先行，
桌宠经 Swift helper 复用同一容器）；加密层（XChaCha20-Poly1305，密钥入
Keychain 与 iCloud Keychain，配恢复码）；年度浅快照压缩任务；自托管 relay
（可选，非 Apple 端真需要时再做）。

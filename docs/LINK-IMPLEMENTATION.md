# 无账号设备连接：实现进度

更新：2026-09-23。Tailscale、虚拟局域网和远程模型调用已按用户要求暂缓。
本文件记录当前代码事实；协议提案见 [MOBILE-PAIRING.md](MOBILE-PAIRING.md)。

## 已落地

| 模块 | 代码与边界 |
| --- | --- |
| 信令服务 | `services/signaling`：真实 WebSocket 服务，仅内存房间、双端 SDP/ICE 协商、TTL、限流、断线清理。尚未部署到公网。 |
| 加密内核 | `core/dozycat-link`：snow 0.10 的 IKpsk2 首次握手、IK 重连、公钥钉住、会话校验指纹、双端批准、持久化确认门槛、作用域/工作区检查。 |
| 有界传输 | 60 KB 明文帧上限、48 KiB 分块、32 MiB 单传输上限、30 秒组装期限；错误密文/重放后丢弃会话。 |
| 原生接口 | UniFFI Swift/Kotlin 生成脚本；私钥和授权记录只用于原生安全存储，不向 JS 暴露。 |
| Apple 密钥存储 | 原生 Keychain adapter，禁止 iCloud 同步，ThisDeviceOnly；同一个条目原子区分 pending/active。代码已编译，测试使用隔离的内存存储，没有读写用户 Keychain。 |
| 实际验证 | 固定 Cacophony 向量、双线程真实 TCP 配对、Loro 小传增量加密/导入/重复导入/重新打开数据库、Swift→Rust 原生集成。 |

## 2026-09-23：接入 Apple 局域网配对

- macOS 设置新增「设备」：二维码只在内存绘制，双端校验确认、取消、重连与移除。
- iOS 新增本地 Expo Module：身份和授权秘密留在原生层，JS 只得到状态/校验码与操作接口。
- 共用 `LinkCoordinator.swift`：Bonjour 发现、Network.framework TCP、有界帧、Noise 握手、Keychain pending→active、每次收发前查本机授权。
- 每个网络回调绑定本次连接 UUID；取消后的旧回调不能修改新连接。批准操作必须携带当时显示的校验码，防止旧界面批准新会话。
- 断线、取消重连不会删除已有 ACTIVE 记录；未完成配对则移除自己写入的 pending。写入失败不开放数据通道。
- 新的原生 TCP 测试运行真实 Network.framework 双端连接，覆盖 QR 解析、双方批准、密文收发、重连、取消、撤销、旧校验码和模拟安全存储写入失败。
- `build-apple.sh` 生成独立 FFI framework slices，避免与已有 DozycatCore 的 modulemap 冲突；Expo 自动链接模块已确认。
- 2026-09-23 本机验证：macOS arm64 Debug 与 iOS arm64 Simulator development build 均通过完整 Xcode 构建（未签名）；手机 TypeScript 检查、16 项测试和 Web 导出通过。这些结果不代表真机验收或商店发布。
- 开发包已安装到独立 iOS 模拟器。界面自动化无法访问本机 Simulator，启动链接停在系统打开确认框，尚未验证应用页面；不将安装成功计为 UI 测试通过。

**仍未组成完整数据同步产品：iOS 开发包接入了局域网配对，Expo Go/Web/Android 不开放配对。小传与能量自动同步尚未接入。**
TCP 测试仅使用 127.0.0.1，并模拟两端用户确认和安全存储；不是相机扫码、Bonjour 跨设备发现、真实 Keychain 权限或公网打洞验收。
信令服务的 SDP/ICE 协商与 Rust 的 ordered-stream 接口尚未由 WebRTC 客户端连接起来。

## 应用协议 v1（当前实现）

- 二维码 room 为 16 字节，PSK 为 32 字节，电脑 X25519 静态公钥为 32 字节。
- 首次连接 `Noise_IKpsk2_25519_ChaChaPoly_SHA256`；后续 `Noise_IK_25519_ChaChaPoly_SHA256`。
- prologue = `dozycat/link/v1/phone-initiator/desktop-responder/` 的 UTF-8 字节后紧接 room 的 16 原始字节。
- Noise 握手只允许空 payload；失败后句柄不可复用。握手哈希经带域分隔 SHA-256，取 128 bit 按 8 组十六进制显示，双方核对。
- 电脑对一张邀请只接受一次候选握手；失败、拒绝后重新生成邀请，避免并发候选替换身份。
- 单调时钟期限贯穿邀请、握手、待确认会话。扫码客户端的墙钟检查只是提前提示。
- 控制帧均位于 Noise 传输内：`01` 批准；`02 || pair_id(16) || discovery_secret(32) || workspace(16) || scope(1)` 绑定提议；`03` 表示本端 pending 已持久化。
- 双方批准后仅电脑能提出绑定。原生端把 peer 保存为 PENDING，再发送 `03`。收齐双方持久化确认后，把本机 ACL 原子改为 ACTIVE，再调用 `activate_after_acl_commit`。
- 中途崩溃首版不自动恢复配对：PENDING 记录绝不用于重连，用户重新扫码；另一端若留下孤立 ACTIVE 条目，需显式移除后重配。这是原提案“幂等恢复确认”的暂时简化。
- 数据帧 `04 || workspace(16) || scope(1) || payload`；首版 scope=1，仅代表小传+能量，不授权模型/文件/终端。接收端仍须校验 payload 的具体业务类型与 CRDT schema。
- 发现房间以 pair_id 作 HKDF salt，从 discovery_secret 派生 discovery key，再用 HMAC 计算 5 分钟时间桶标识。**重连信令的独立 AEAD 封装尚未实现**，不可把当前明文 SDP 服务当作完整隐私发现协议。
- 撤销时原生协调器必须先删除 ACTIVE ACL、关闭现有会话，再停止发现；每次导入前重查 ACL。内核里的 Peer 是快照，不能替代原生端对全部活动连接的撤销管理。

## 尚需完成，不能宣称已支持

1. 已有 Apple 双端界面与原生协调器；继续完成真机相机扫码、局域网权限和后台生命周期验收。
2. Android Keystore、原生发现/网络 adapter 与 development build 集成；iOS 本地原生模块已接入。
3. WebRTC DataChannel、STUN/公网打洞；已有 Bonjour/TCP 的局域网实现，不引入默认业务密文中继。
4. 手机上的 Loro 原生接入与当前 JSON 文档无损迁移，版本向量/ACK/快照流程、恶意 CRDT 输入资源限制。
5. 身份/ACL 与卸载、系统恢复的联合处理；原生端身份缺失时必须让旧授权失效。
6. 信令部署、代理日志/备份/swap 验收、真机扫码/锁屏/断网恢复/撤销测试。

协议内核没有安全审计结论。本地 SQLite 加密和系统备份排除仍是独立未完成项。

## 复现

```sh
npm ci --prefix services/signaling
npm test --prefix services/signaling
npm start --prefix services/signaling
cargo test --locked --manifest-path core/dozycat-link/Cargo.toml
core/dozycat-link/scripts/test-native.sh
```

原生测试会生成忽略的 `core/dozycat-link/target/generated` Swift/Kotlin 绑定，编译 Swift
测试程序并链接 Rust 动态库。Kotlin 生成不等于 Android 编译或真机验证。

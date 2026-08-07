# dozycat · 懒猫

**一个不帮你干活的 AI。** 它住在你的桌面和手机里，记得你的一切，用「心理能量」
和「生理能量」两条刻度轻轻记着你的状态，提醒你休息、喝水、睡觉。
工作交给别的 AI，它只负责你。

设计源（spec）：[dozycat v2 · Claude Design](https://claude.ai/design/p/17a7d3cc-5126-44af-8c0d-a3e54757796f?file=dozycat+v2.dc.html)

## 仓库结构

```
apps/
  ios/        SwiftUI 原生 app（iOS 优先，目标 App Store 上架）
  desktop/
    pet-mac/                macOS 桌宠（AppKit 壳 + SwiftUI 内容，与 iOS 共用 CatFace/DS，见 docs/DESKTOP-UI.md）
    crates/dozycat-sense/   内容盲疲劳感知守护（喂 JSONL 给桌宠，见 docs/FATIGUE.md）
core/
  dozycat-core/   小传+能量共享内核（CRDT 同步，见 docs/MEMORY-SYNC.md）
docs/
  MEMORY-SYNC.md        多端同步选型（Loro + E2EE + CloudKit）
  FATIGUE.md            疲劳模型（内容盲感知 → 能量 → 补血）
  MOMENTS-PIPELINE.md   桌面观屏 → 小传管线（5min sequence → 每日 ≤3 条蒸馏）
  DESKTOP-UI.md         桌面 UI 选型与手艺（学 sheru：AppKit 壳 + SwiftUI 内容）
  RELEASE.md            发布与审核选型（iOS App Store / macOS 直发公证）
site/         官网（静态页，中文根路径 + /en/，实现自「dozycat 官网.dc.html」）
design/       设计稿指针（源在 Claude Design）
```

## iOS（apps/ios）

- Xcode 项目由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成；
  依赖 dozycat-core（Rust，经 UniFFI）：
  ```sh
  cd apps/ios
  ./scripts/build-core.sh   # Rust → DozycatCore.xcframework + Swift 绑定
  xcodegen generate
  xcodebuild -project Dozycat.xcodeproj -scheme Dozycat \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```
- Bundle id `com.paperboytm.dozycat`，iOS 17+，竖屏，中文优先。
- 已实现（对齐 v2 设计稿）：
  - **今日** — 呼吸/眨眼的懒猫、按时段问候、心理/生理能量、喝水/散步/睡前清单
  - **聊天** — 记忆引用注脚、快捷回复、可发送（占位回复，后续接真模型）
  - **小传**（产品词，原「记忆」）— 分类筛选（全部/开心的/身体/人）+ 全文搜索，
    **真存储**：dozycat-core（Loro CRDT + SQLite），首启种子、重启持久
  - **多语种** — String Catalog（开发语言 zh-Hans，中文原文即 key），已带英文；
    界面/文案随系统语言，种子数据按首启语言写入
  - **设置** — 语言（系统级 per-app 语言入口）+ **BYOK**：OpenAI / DeepSeek /
    自定义 OpenAI 兼容端点，Key 只存本机 Keychain；配好后聊天走真模型
    （懒猫人设 prompt），未配置回退内置回复
  - **回顾** — 一周能量曲线、睡眠/起身统计、懒猫的话
  - **睡前模式** — 全屏暗色（三件小事、呼吸/雨声、晚安）
  - **休息时刻** — 全屏休息卡 + 5 分钟倒计时，休息回生理能量并落跨端账本
- DEBUG 截图钩子：`-initialTab chat|memory|review`、`-showSleep 1`、`-showRest 1`。
- 后续：CKSyncEngine 传输 + 加密层（见 docs/MEMORY-SYNC.md 里程碑 3-4）、
  HealthKit（睡眠/步数 → 生理能量）、通知（锁屏主动关心，设计稿 06）、
  真 agent 接入、App Icon、签名与 TestFlight。

## 桌宠（apps/desktop）

单原生进程：pocket-widget（透明置顶壳）+ pocket-pi（QuickJS agent 脑），
详见 [apps/desktop/README.md](apps/desktop/README.md)。目前是脚手架 + 计划。

## 设计原则

奶油纸感底色（#FAFAF8/#EDECE8）、墨色 #2E2E33、生理 = 珊瑚 #FF8A75、
心理 = 蓝灰 #7C8DB5；猫是纯代码几何（无切图），一直「有点活着」——
呼吸 3.4s、每 ~6s 眨一次眼。文案永远是懒猫的第一人称，轻、短、不说教。

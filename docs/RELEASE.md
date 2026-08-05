# 发布与审核 — 选型定案

目标：苹果侧发布。iOS 走 App Store；**macOS 桌宠走 Developer ID 直发（公证），
不上 Mac App Store**。这是本仓库最重要的发布决策，理由见下。

## 当前架构对审核难不难？——不难（iOS 侧）

| 点 | 审核视角 |
|---|---|
| SwiftUI + XcodeGen + Rust 静态库（UniFFI） | 完全常规。静态链接进主二进制，无动态库/私有 API 问题；App Store 上大量 Rust 内核先例 |
| BYOK（用户自带 OpenAI/DeepSeek Key） | 允许，先例众多。注意：①不能在 app 内卖/代充 Key（会触发 IAP 3.1.1）；②隐私标签要如实标「用户内容 → 发给用户自选的第三方模型」；③设置页已写明 Key 只存本机 Keychain——这句要保留 |
| 聊天内容出设备 | 用户主动配置 + 明示，合规。首次配 Key 时可加一次确认弹层（上架前补） |
| CloudKit 同步（里程碑 3） | Apple 自家轨道，零额外审核负担 |
| HealthKit（未来） | 需要用途文案 + 只读权限，常规 |

**iOS 结论：现架构没有任何审核硬伤。** 首次提审周期：账号资料/隐私标签/截图
准备 2-3 天 + 审核通常 24-72h；被拒也多是元数据级（改文案重提，快）。
TestFlight 内测先行：首个构建审核 ~1 天，之后秒过。

## macOS 为什么不上 Mac App Store

桌宠的核心输入是**屏幕/键鼠观测**（MOMENTS-PIPELINE.md + FATIGUE.md）：

- MAS 强制 App Sandbox：全局输入计数、事件监听在沙盒里不可用/受限；
  ScreenCaptureKit 沙盒内可用但每次会话要用户交互选择，「常驻默默观察」
  的产品形态与沙盒模型直接冲突
- 即便技术上绕过，「持续截屏 + 键鼠监控」在 MAS 人工审核里是高风险类目

**Developer ID + 公证（notarization）直发**没有这些问题：
`notarytool` 提交是**自动化扫描，分钟级返回，无人工审核**；
权限走系统 TCC 弹窗（屏幕录制/辅助功能授权），用户自主。
更新用 **Sparkle 2**（行业标准自更新框架）。分发 = 官网/GitHub Releases 的
dmg。将来若做「无观屏的纯桌宠版」可另出 MAS 版本，不必现在纠结。

## 发布流水线（SOTA，尽量少运维）

- **iOS：Xcode Cloud**（Apple 原生 CI）。证书/描述文件全自动管理，
  push → 构建 → TestFlight 自动分发；免费额度 25 小时/月对我们绰绰有余。
  仓库已是 XcodeGen + Rust，需要一个 `ci_scripts/ci_post_clone.sh`：
  装 rustup targets → `./scripts/build-core.sh` → `xcodegen generate`
- **macOS：GitHub Actions**。`xcodebuild archive` → `codesign`（Developer ID
  Application 证书）→ `xcrun notarytool submit --wait` → `stapler` → dmg 上
  GitHub Releases；Sparkle appcast 一并生成。证书以 base64 存 repo secrets
- 版本纪律：`MARKETING_VERSION` 单一来源在 project.yml；tag 触发发布

## 上架前 checklist（iOS）

1. App Store Connect：建 app、类目（生活/健康）、隐私标签（诊断无、
   用户内容→第三方 AI【仅 BYOK 配置后】、健康数据【接 HealthKit 后】）
2. 首配 Key 的确认弹层 + 隐私政策页（静态页即可）
3. 真机资产：6.9"/6.5" 截图、App 预览可选；图标已就位
4. 加密出口合规：仅用 HTTPS/系统加密 → `ITSAppUsesNonExemptEncryption = NO`
5. TestFlight 内测一轮 → 提审

## 周期预期

| 事项 | 周期 |
|---|---|
| TestFlight 首个构建 | 提交后 ~1 天 |
| App Store 首次提审 | 准备 2-3 天 + 审核 24-72h；含一次被拒缓冲，**~1-2 周拿到上架** |
| 后续版本更新 | 审核通常 <24-48h，可用 phased release |
| macOS 直发 | 公证分钟级，**当天可发**；Sparkle 更新即时 |

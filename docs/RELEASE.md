# 发布与审核 — 选型定案

目标是苹果侧发布。iOS 走 App Store；macOS 桌宠走 Developer ID 直发（公证），
不上 Mac App Store。这是本仓库最重要的一条发布决策，理由在下面。

## iOS 过审难不难——不难

逐条过一遍审核视角。SwiftUI 加 XcodeGen 加 Rust 静态库（UniFFI）：完全常规，
静态链接进主二进制，没有动态库和私有 API 的问题，App Store 上 Rust 内核的先例
一大把。BYOK、用户自带 OpenAI 或 DeepSeek 的 Key：允许，先例众多——但有三条要
守住：不能在 app 内卖 Key 或代充（会触发 IAP 3.1.1）；隐私标签要如实标「用户内容
会发给用户自选的第三方模型」；设置页那句「Key 只存本机钥匙串」要保留。聊天内容
出设备：用户主动配置加明示，合规，首次配 Key 时补一层确认弹窗即可。CloudKit
同步是 Apple 自家轨道，零额外负担。将来接 HealthKit，写清用途文案、只读权限，
也是常规操作。

结论：现架构在 iOS 侧没有任何审核硬伤。首次提审的周期，账号资料、隐私标签、
截图准备两三天，审核通常 24 到 72 小时；被拒也多是元数据级的，改文案重提很快。
先走 TestFlight 内测：首个构建审核约一天，之后秒过。

## macOS 为什么不上 Mac App Store

桌宠的核心输入是屏幕和键鼠的持续观测（见 MOMENTS-PIPELINE.md 和 FATIGUE.md），
这与 MAS 的沙盒模型正面相撞：App Sandbox 强制开启后，全局输入计数和事件监听
不可用或受限；ScreenCaptureKit 在沙盒里虽然能用，但每次会话都要用户交互式选择，
「常驻默默观察」的产品形态根本立不住。就算技术上绕过去，「持续截屏加键鼠监控」
在 MAS 的人工审核里也是高风险类目。

Developer ID 加公证（notarization）直发没有这些问题：`notarytool` 提交走的是
自动化扫描，分钟级返回，无人工审核；权限走系统的 TCC 弹窗（屏幕录制、辅助功能），
用户自主授权。更新用 Sparkle 2，行业标准的自更新框架；分发就是官网或 GitHub
Releases 上的一个 dmg。将来若想做无观屏的纯桌宠版，可以另出一个 MAS 版本，
不必现在纠结。

## 发布流水线，尽量少运维

iOS 用 Xcode Cloud（Apple 原生 CI）：证书和描述文件全自动管理，push 即构建、
自动分发 TestFlight，免费额度每月 25 小时对我们绰绰有余。仓库已经是 XcodeGen
加 Rust，只需要一个 `ci_scripts/ci_post_clone.sh`：装 rustup targets，跑
`./scripts/build-core.sh`，再 `xcodegen generate`。

macOS 在发布者本机打包：Developer ID Application 证书和 Sparkle EdDSA 私钥只留
在本机钥匙串，`codesign`、`xcrun notarytool submit --wait`、`stapler` 全部本地跑；
GitHub 只接收已经签名并公证好的 dmg Release 附件，以及公开的 appcast。证书、
私钥和 Apple 登录凭证不上传到 GitHub（包括 GitHub Secrets）。版本纪律：
`MARKETING_VERSION` 的单一来源在 project.yml。

## iOS 上架前的清单

App Store Connect 建 app，类目选生活或健康，隐私标签如实填（诊断无；用户内容
发第三方 AI，仅 BYOK 配置后；健康数据，接 HealthKit 后）。首配 Key 的确认弹窗
和一页静态的隐私政策。真机资产：6.9 寸和 6.5 寸截图，App 预览可选，图标已就位。
加密出口合规：只用 HTTPS 和系统加密，`ITSAppUsesNonExemptEncryption = NO`。
TestFlight 内测一轮，然后提审。

## 周期预期

TestFlight 首个构建，提交后约一天。App Store 首次提审，准备两三天加审核 24 到
72 小时，含一次被拒的缓冲，一到两周拿到上架。后续版本更新通常 24 到 48 小时内
过审，可以用 phased release。macOS 直发公证是分钟级的，当天可发，Sparkle 更新
即时到达。

## macOS 发布怎么走（Sparkle 已接好）

自动更新用 Sparkle 2，代码和打包链路都已接通，跑一次验证过（adhoc）：

- **设置里的更新**：设置 → 常规 → 更新，有「当前版本」「自动检查更新」开关
  和「检查更新」按钮。默认后台每天查一次官网的 appcast（`Updater.swift`，
  Info.plist 的 `SUEnableAutomaticChecks` / `SUScheduledCheckInterval`）。
- **签名密钥**：更新包用 EdDSA 签名。私钥在发布者本机钥匙串（`generate_keys`
  生成），公钥 `SUPublicEDKey` 写在 project.yml 的 Info.plist 段。换发布者要
  重新 `generate_keys` 并同步改公钥、重签所有历史 appcast。
- **一条命令出 dmg**：`scripts/package-dmg.sh`——Release 构建 → 嵌 sense →
  **Sparkle.framework inside-out 签名**（XPC 服务、Autoupdate、Updater.app 逐层）
  → Developer ID 签 app（hardened runtime）→ dmg → 公证 → 钉票。正式模式每次
  自动把 `MARKETING_VERSION` 的 patch 位 +1（adhoc 验证不消耗版本号）。
- **appcast**：`scripts/make-appcast.sh` 从 dist 里的 dmg 生成并签名
  `site/appcast.xml`，下载地址指向 GitHub Releases（`DOZYCAT_DL_PREFIX` 可改）。

发一版的完整动作：

1. `scripts/package-dmg.sh`（需 Developer ID 证书 + `DOZYCAT_NOTARY_PROFILE`）
   出 `dist/dozycat-<版本>-arm64.dmg`，已公证钉票。
2. 把这个 dmg 传到 GitHub Releases（tag = 版本号）。
3. `scripts/make-appcast.sh` 生成 `site/appcast.xml`，连同 project.yml 的版本号
   一起提交、推到 main。
4. GitHub Pages 部署 `site/`，`SUFeedURL`（`https://dozycat.github.io/dozycat/appcast.xml`）
   即生效，老版本下次检查就能看到更新。

**凭证只放钥匙串或 CI secrets，绝不提交到仓库。** 发布机需要一张有效的
Developer ID Application 证书，以及用 `xcrun notarytool store-credentials`
保存的公证 profile。发布前可分别用下面两条命令做无密钥回显的检查：

```bash
security find-identity -v -p codesigning
xcrun notarytool history --keychain-profile "$DOZYCAT_NOTARY_PROFILE"
```

本地正式打包时只传 profile 名称（它不是密码），例如：

```bash
DOZYCAT_NOTARY_PROFILE=dozycat-notary scripts/package-dmg.sh
```

`.env`、Apple 私钥/证书导出文件和 provisioning profile 均已由仓库根目录的
`.gitignore` 排除；Apple ID 密码、app-specific password 和私钥不要写进脚本、
文档、提交记录或构建日志。

# dozycat mobile

Expo SDK 57 / React Native 0.86.3 手机应用，支持 Expo Go。无产品账号，本地优先。

底部导航仅保留「今日、小传、设置」。倾诉、回顾和模型配置已撤下；既有本地数据仍保留。

## 已实现

- 今日：按桌面 DeskCat 比例移植的猫咪、呼吸/眨眼、分时问候、喝水记录与撤销、散步记录、首次介绍。
- 能量：用户自评心理/生理能量；跨日刷新，未记录时保持空白。
- 小传：创建、编辑、删除确认、分类与全文子串搜索，持久化与 5000 条边界。
- 休息：1/3/5/10 分钟计时，按绝对时间跨锁屏/重启恢复，回到页面结算且不重复计数。
- 睡前：暗色页面、三件小事清单、睡前小传、晚安时刻记录。
- 设置：喝水目标、用户主动授权的本机睡前提醒。
- 数据：明文 JSON 小传导出、校验后合并导入、重复 ID 保留本地修改。
- 设备：iOS development build 可调用原生同 Wi-Fi 配对、双端校验确认、重连和移除；Expo Go/Web/Android 显示未启用状态。**尚未接入小传自动同步和公网连接，真机验收待完成。**

手机数据使用 `expo-sqlite/kv-store`，Web 预览使用当前 origin 的 localStorage。
写入按顺序执行，失败显示重试；数据损坏时停止写入并提供原始数据导出。

## 运行

在本目录用 Node.js LTS（至少 22.13）执行：

```sh
npm ci
npm start
```

手机安装支持 SDK 57 的 Expo Go，与电脑处于同一局域网，扫描终端二维码。
`./script/build_and_run.sh` 也可启动，支持 Codex 自带 Node；将此目录添加为 Codex
项目后，`.codex/environments/environment.toml` 提供 Run 动作。

```sh
./script/build_and_run.sh --ios
./script/build_and_run.sh --android
./script/build_and_run.sh --web
npm run typecheck
npm test
npx expo-doctor
npx expo export --platform all
```

`npm test` 使用 Node 内置 TypeScript stripping，推荐 Node 24 LTS。
打包导出验证 JS/Hermes 与资产，不等于完成 Xcode/Gradle 构建或真机测试。
Web 不支持本地定时通知。
相机、通知权限、键盘、安全存储、系统分享需 iOS / Android 真机验收。

## 原生设备连接开发包（iOS）

先准备 Rust/Swift 接口及静态 framework，再安装 CocoaPods 依赖并构建：

```sh
npm ci
npm run ios
```

`npm run ios` 调用 `./script/build_and_run.sh --build-ios`，先执行 `prepare:link:apple`，
再执行 `expo run:ios`。需要完整 Xcode、Rust 的 Apple device/simulator/macOS targets、
Node 和 CocoaPods。默认 `npm start` 仍使用 Expo Go；已安装开发包时使用
`./script/build_and_run.sh --dev-client`。原生代码变化后必须重建安装包，热更新不会添加模块。

电脑端使用 `apps/desktop/pet-mac/scripts/install-debug.sh` 构建；设置 → 设备 → 添加手机。
手机打开设置 → 我的设备，扫码后完整核对八组校验码，两端分别确认。
当前只接同一 Wi-Fi 的 Bonjour/TCP；双端绑定后需要在设备页主动重连。
连接成功表示设备授权与 Noise 通道就绪，**不表示小传已经同步**。

## EAS

app.json 已配置用户指定的 project ID：`ef1ec4c9-8b22-49d3-90a2-80faed3598d5`。
本机尚未登录，项目所属账号与权限未在线验证：

```sh
npx eas-cli@latest login --browser
npx eas-cli@latest init --id ef1ec4c9-8b22-49d3-90a2-80faed3598d5
```

`eas.json` 提供 preview 内部分发和 production 构建配置。没有自动触发云构建、
OTA 发布或商店提交。EAS 关联不是产品用户登录，也不创建数据同步后端。

## 实现边界与下一阶段

- iOS 已接入 Rust Noise 原生绑定；Loro 原生数据层、旧 SwiftUI 数据迁移、HealthKit / Health Connect 尚未接入。
- 本地 SQLite 尚未做应用级加密。Android 独立构建禁用系统备份；iOS 数据目录备份排除待实现。
  Expo Go 的系统备份行为由宿主应用控制，不可当作独立包的隐私验收。
- 配对页读取 `dozycat://pair?data=<URL encoded JSON>`；邀请只在内存解析，不记录或传送秘密。
  iOS 原生模块与桌面 responder 完成认证、双端确认和本机授权持久化后才开放加密通道；业务同步尚未接入。
  邀请格式校验不是认证，UI 状态也不是已配对凭据。
- development build 包含原生连接模块；Expo Go 并不包含 Rust 加密层。
- 小传导出是用户可读的明文文件，不是加密全量恢复备份。全部设备与备份丢失时无法恢复。

架构和协议提案见 [手机与设备绑定](../../docs/MOBILE-PAIRING.md)。

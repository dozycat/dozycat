# dozycat-desktop — 最小化桌宠

白天安静待在角落的懒猫（设计稿 07/08 屏）。**不用 Electron。**

当前形态（已运行）：**`pet-mac/` SwiftUI 壳 + `dozycat-sense` Rust 守护**——
壳是透明置顶窗（与 iOS 共用 CatFace/DS，多语种同一套 String Catalog），
守护进程独占能量账本并输出 JSONL 语义流（pb-os 式组合：原始计数不出守护，
UI 只见语义）。菜单栏显示「懒猫 45」，nudge 走猫旁气泡。

> 选型注记：原计划的 pocket-widget（3D 壳）适合 cat-poc 的低多边形场景；
> v2 设计是扁平白团子猫，SwiftUI 原生壳更贴（且与 iOS 共享代码与签名链路）。
> pocket-pi 作为 agent 大脑的计划不变，经 dozycat-core FFI 接入。

## 架构（沿用 cat-poc 的三层）

| 层 | 来源 | dozycat 的差异 |
|---|---|---|
| 壳 | [pocketjs / pocket-widget](https://github.com/pocket-stack/pocketjs) — 透明、置顶、demand-render 的 widget 窗口 | 场景不是 3D 低多边形猫+显示器，而是 v2 设计稿的**扁平白团子猫**（程序化几何：耳朵两块、头一块、眨眼/呼吸逐帧摆位，无资产文件） |
| 脑 | [pocket-pi](https://github.com/pocket-stack/pocket-pi) — pi agent 跑在 QuickJS，无 Node | 同 cat-poc：widget 的帧泵同时泵 agent，一个心跳两个运行时 |
| 感知 | cat-poc 的 `cat-sense`（secure-input 门控 → 隐私黑名单 → 截屏去重）；更完整的参照是 `~/workspace/cat` 的 pb-os（collector → 私有 L0 → projector → 语义流） | **已实现 v0：`crates/dozycat-sense`** —— 内容盲疲劳感知（输入频率计数器 + 空闲 + 前台 app 切换 + 会议启发式 → 能量模型 + 补血 nudge），`cargo run -p dozycat-sense` 直接出 JSONL 语义流。模型与规则见 [docs/FATIGUE.md](../../docs/FATIGUE.md) |

产品行为（对应设计稿）：

- **07 桌面常驻**：猫待在屏幕角落呼吸、眨眼；菜单栏显示 `懒猫 45`（生理能量）。
  坐满一段时间后，猫旁边冒一条气泡：「坐了 1 小时 50 分……去接杯水回血？」
- **08 休息时刻**：到点后弹出全屏休息卡（桌面轻轻暗下来），倒计时 5 分钟，
  「休息 5 分钟 / 3 分钟后再叫我」。
- 与 iOS app 共享同一套「心理/生理能量 + 记忆」数据模型（同步层后续定，
  优先 CloudKit，屏内文案强调「只存在你自己的设备里」）。

## 起步

vendor 子模块尚未添加。本机开发期可以直接 path-dep 到旁边的 checkout：

```toml
# crates/dozycat-pet/Cargo.toml （开发期）
pocket-widget = { path = "../../../../cat-poc/vendor/pocketjs/crates/pocket-widget" }
```

定型后改为本仓库的 git submodule（与 cat-poc 相同的 `vendor/` 布局），并对齐
它固定的 `wgpu` / `winit` / `glam` 版本。

## 里程碑

1. `dozycat-pet` 打开透明置顶窗口，画出会呼吸、眨眼的白团子猫（对齐 v2 设计稿的比例与配色）
2. ~~疲劳感知~~ → **`dozycat-sense` v0 已落地**；接入 pet 进程：Minute 流驱动
   菜单栏「懒猫 45」与猫的气泡，Nudge 流驱动全屏休息卡（设计稿 08）
3. 感知 v1：麦克风/摄像头占用检测（替代会议 app 启发式）、NSWorkspace 通知、EventKit 日历前瞻
4. 能量/记忆写入 `core/dozycat-core`，与 iOS 多端同步（docs/MEMORY-SYNC.md）
5. Pocket Pi 接入：点猫可以说话，记忆读写同一内核
6. 打包 `.app` + 签名公证（Developer ID），上架另议（桌宠走直接分发更顺）

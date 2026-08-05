# 疲劳感知 — 观测你干得多累，不观测你在干啥

真人 agent 的输入源是对屏幕/设备的持续观测。架构参照
`~/workspace/cat` 的 pb-os（`apps/paperboy/plugins/pb-os/ARCHITECTURE.md`）：

```text
Collectors → 私有 L0 → OutputProjector（唯一的 raw→semantic 边界）→ 小语义流
```

pb-os 的铁律是「原始击键/截图永远不出守护进程」。dozycat 把这条边界再收紧
一档：**采集层就是内容盲的**。pb-os 学「你在干啥」（context window），
dozycat 只学「你干得多累」（labor window）——我们不需要键入的内容、
屏幕的像素，只需要*强度、节奏、时长*。

## 信号（macOS，`dozycat-sense`）

| 信号 | 来源 | 内容盲？ |
|---|---|---|
| 击键/点击/滚动 **频率** | `CGEventSourceCounterForEventType`（系统级计数器，非事件流，无需辅助功能权限） | ✅ 只有计数，无键值 |
| 空闲时长 | `CGEventSourceSecondsSinceLastEventType` | ✅ |
| 前台 app + 切换频率 | `lsappinfo`（v1 换 NSWorkspace 通知） | app 名，不读窗口内容 |
| 会议中 | v0：前台 app 启发式（Zoom/Teams/FaceTime/腾讯会议…）；v1：麦克风/摄像头占用（CoreAudio/AVCapture）——比 app 名可靠 | ✅ 只有布尔 |
| 日历 | v1：EventKit（「3 点有会」→ 提前留体力） | 只读忙闲 |
| iOS 侧 | HealthKit（睡眠/步数/心率变异）、DeviceActivity；iOS 无法持续观测屏幕——桌面侧的疲劳状态经记忆同步到手机（见 MEMORY-SYNC.md 的 `energy`/`ledger`） | ✅ |

隐私承诺（写进产品文案）：**无键值记录、无截屏、无窗口内容读取；
所有原始计数不出本机，跨设备只同步「能量数字 + 事件」密文。**

## 能量模型（v0，实现于 `dozycat-sense/src/lib.rs`，两端共用同一套常数）

每分钟一个采样 `MinuteSample { keys, clicks, scrolls, switches, front_app, meeting, idle }`，
折算劳动强度 `i ∈ [0,1]`：

```text
i = clamp( 0.5·min(keys/300, 1) + 0.3·min(clicks+scrolls)/60, 1) + 0.2·min(switches/6, 1) )
会议分钟：i = max(i, 0.7)          // 开会 = 持续高强度输出，哪怕手不动
```

- **生理能量**（坐着本身 + 输出量）：活跃分钟 `drain = 0.10 + 0.25·i`
  （摸鱼 ≈ 6 点/时，高强度 ≈ 21 点/时）
- **心理能量**（切换损耗 + 会议 + 连续专注）：
  `drain = 0.05 + 0.20·switch_factor + 0.25·(meeting) + 0.10·(连续活跃>60min)`
- **回血**：连续空闲 ≥3 分钟起算（真的离开了，不是停下来想事），
  生理 +0.5/min、心理 +0.3/min；会议中不回血
- 天花板 100，地板 0；睡眠（iOS/HealthKit）夜间重置

## 补血规则（nudge，语义输出）

| 触发 | 懒猫说 |
|---|---|
| 连续活跃 ≥90 min | 「坐了 N 分钟啦，去接杯水回血？」 |
| **会议结束**（会议态持续 ≥20 min 后消失，且连续 3 min 确认——中途切出去记笔记不算结束） | 「会开完了吧？高强度输出后要补血，起来走两步～」 |
| 生理 < 30 | 「生理能量掉到 N 了，眼睛离开屏幕一会儿好不好？」 |
| 高切换率持续（心理磨损） | 「感觉你在好多事之间跳，挑一件收个尾？」 |

Nudge 有冷却（同类 ≥45 min），永不弹连环——懒猫轻轻说一次就好。

## 数据流与落点

```text
dozycat-sense（桌宠进程内一个线程，5s tick → 1min 聚合）
  → EnergyModel.step() → JSONL 语义流
      ├─ Minute  … 桌宠 UI（菜单栏「懒猫 45」、猫的气泡）
      └─ Nudge   … 弹卡（设计稿 08）/ 通知
  → 写入 dozycat-core 的 energy + ledger → 同步 → iOS「今日」页实时同款数字
```

v0 已实现：计数采集、强度折算、能量模型、nudge 引擎（含冷却）、JSONL 输出，
**能量已落 dozycat-core 账本**（`DOZYCAT_STORE`，默认 `~/.dozycat/store.db`），
重启从账本续算——跨端合并后最新一条可能来自手机，桌面直接接续。
`cargo test` 覆盖典型日：高强度编码、长会+会后补血提示、离开回血。
下一步：麦克风占用检测替代 app 启发式、NSWorkspace 通知、接入桌宠 UI、
EventKit 前瞻、iOS HealthKit 侧写入同一 ledger。

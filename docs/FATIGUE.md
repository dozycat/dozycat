# 疲劳感知 — 观测你干得多累，不观测你在干啥

真人这个 agent 的输入，是对屏幕和设备的持续观测。这套架构承自 pb-os
（`~/workspace/cat`，`apps/paperboy/plugins/pb-os/ARCHITECTURE.md`）：采集器把原始
数据收进一个私有的 L0，经过唯一一道 raw→semantic 的边界，投影成一条很小的语义流。
pb-os 的铁律是原始击键和截图永远不出守护进程。dozycat 把这条边界又往里收了一档：
**采集层本身就是内容盲的**。pb-os 想知道你在干啥（context window），dozycat 只想
知道你干得多累（labor window）——键入了什么、屏幕上有什么，一概不需要；需要的
只有强度、节奏、时长。

## 它看得见什么

击键、点击、滚动，看的都是频率，不是内容——用的是
`CGEventSourceCounterForEventType`，一个系统级计数器，不是事件流，连辅助功能权限
都不用申请，天然只有数字没有键值。空闲了多久，问
`CGEventSourceSecondsSinceLastEventType`。前台是哪个 app、切换得多不多，v0 用
`lsappinfo`，v1 换成 NSWorkspace 通知；读的是 app 名，不碰窗口内容。在不在开会，
v0 靠前台 app 猜（Zoom、Teams、FaceTime、腾讯会议这些），v1 改看麦克风和摄像头的
占用（CoreAudio / AVCapture）——比 app 名可靠，而且给出的只是一个布尔。日历在
v1 经 EventKit 只读忙闲，「三点有会」可以提前留体力。手机那侧走 HealthKit
（睡眠、步数、心率变异）和 DeviceActivity；iOS 没法持续观测屏幕，桌面算出的疲劳
状态经记忆同步流到手机上去（见 MEMORY-SYNC.md 的 `energy` 与 `ledger`）。

写进产品文案的隐私承诺，一句话：**无键值记录、无截屏、无窗口内容读取；所有原始
计数不出本机，跨设备只同步「能量数字 + 事件」的密文。**

## 能量怎么算（v0，实现在 `dozycat-sense/src/lib.rs`，两端共用同一套常数）

每分钟聚一个采样 `MinuteSample { keys, clicks, scrolls, switches, front_app,
meeting, idle }`，折算成劳动强度 `i ∈ [0,1]`：

```text
i = clamp( 0.5·min(keys/300, 1) + 0.3·min((clicks+scrolls)/60, 1) + 0.2·min(switches/6, 1) )
会议分钟：i = max(i, 0.7)     // 开会是持续的高强度输出，哪怕手不动
```

生理能量掉在「坐着本身 + 输出量」上：活跃的每分钟 `drain = 0.10 + 0.25·i`，
摸鱼约合每小时 6 点，高强度约 21 点。心理能量掉在切换损耗、会议和连续专注上：
`drain = 0.05 + 0.20·switch_factor + 0.25·(meeting) + 0.10·(连续活跃>60min)`。
回血要等连续空闲满 3 分钟才起算——真的离开了，不是停下来想事——生理每分钟
+0.5，心理 +0.3；会议中不回血。天花板 100，地板 0；夜里的睡眠（iOS/HealthKit）
负责重置。

## 它什么时候开口

连续活跃满 90 分钟，它说「坐了 N 分钟啦，去接杯水回血？」。会议态持续了 20 分钟
以上、又连续 3 分钟消失（中途切出去记笔记不算散会），它说「会开完了吧？高强度
输出后要补血，起来走两步～」。生理掉破 30，它说「生理能量掉到 N 了，眼睛离开屏幕
一会儿好不好？」。切换率居高不下、心理在磨损，它说「感觉你在好多事之间跳，挑一件
收个尾？」。同类提醒之间隔至少 45 分钟，永远不弹连环——懒猫轻轻说一次就好。

## 数据从哪来、落到哪去

```text
dozycat-sense（桌宠进程内一个线程，5s tick → 1min 聚合）
  → EnergyModel.step() → JSONL 语义流
      ├─ Minute … 桌宠 UI（菜单栏「懒猫 45」、猫的气泡）
      └─ Nudge  … 弹卡（设计稿 08）/ 通知
  → 写入 dozycat-core 的 energy + ledger → 同步 → iOS「今日」页实时同款数字
```

v0 已经跑起来的：计数采集、强度折算、能量模型、带冷却的 nudge 引擎、JSONL 输出；
能量落进了 dozycat-core 的账本（`DOZYCAT_STORE`，默认 `~/.dozycat/store.db`），
重启从账本接着算——跨端合并后最新一条可能来自手机，桌面直接续上。`cargo test`
盖住了几个典型的日子：高强度编码的一天、长会加会后提醒的一天、离开回血的一天。
往后排的：麦克风占用检测替掉 app 启发式、NSWorkspace 通知、接进桌宠 UI、EventKit
的前瞻、iOS 把 HealthKit 写进同一本账。

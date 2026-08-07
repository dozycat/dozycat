# dozycat 的 agent 体系

桌面和手机上的智能行为，不再是一次次零散的 LLM 调用，而是跑在 agent 执行器上。
执行器按平台分两档。桌面首选真 pi（`PiCLI.swift`）：pet 直接 spawn 本机的 `pi`
CLI，梦、找线索、聊天都用 pi 自带的 read/bash/edit/write 工具跑在花园目录上，
session 落在 `~/.pi/agent/sessions`（project 是 `~/.dozycat/garden`），打开 pi 的
session 浏览器就能看到「dozycat·梦」「dozycat·找线索」「dozycat·聊天」。值得记的
小事经 `moments_inbox.jsonl` 交接，由 pet 收件入库——store 的单写者约定不破。
没装 pi 的机器和 iOS 走内置循环（`PiAgent.swift`，OpenAI 兼容的 function
calling），行为定义和 pi 档完全同构；面向上架的自包含运行时是 pocket-pi
（QuickJS），到时候行为原样迁移。

## 三个 agent，各管一段

**sequence** 每五分钟跑一回：屏幕文字（本机 Vision OCR）、前台 app、能量和久坐
时长喂给模型，白描两三句，只写可见的事实，落成
`notes/<日期>/<HHmm>_note.md`。**dream** 每十二次 sequence 或睡前跑一回：翻当天
的笔记和已有的人物卡，搞清楚三件事——谁反复出现、这段关系最近的温度、用户本人
累不累答应过什么——更新 `people/<名>.md`，往小传里存每天至多三条真正值得记住的
小事（进 core，跨端同步）；笔记里出现的、和用户有关的本机文件路径与网页链接，
用 link_file / link_url 留成 `links/<名>.md` 链接卡（花园是搜索的地基，值得再
找到的东西都要有一张卡）；最后写一篇不超过五句的梦记。**searcher** 在 ⌥空格
接到一句完整的问题时出动（agentic RAG）：拿着 search_moments、grep_notes、
read_note、人物卡、grep_links 和 mdfind 这些工具多轮翻找（花园里都没有才搜本机
文件），输出「推理：/结论：」两行——推理说线索怎么串起来的、出自哪，结论直接
回答。UI 把这两行渲染成结案报告（证物列清楚、盖「本猫断定」章），存档进
`cases/<日期>-案卷N.md`，《传》可取材。聊天在两端都一样：persona 加上最近的
小传当上下文，带一个 save_moment 工具，值得记的它自己存，闲聊不存。

## 数据地盘（全部本机、纯 markdown、用户可翻）

```
~/.dozycat/garden/
  notes/2026-08-06/1022_note.md   sequence 的时间笔记（frontmatter：本地时间/app/能量）
  people/番薯.md                   人物卡：关系一句话、最近温度、带日期的证据
  links/番薯的合照.md              链接卡：target 指向本机文件或网页（frontmatter：target/date/why）
  cases/2026-08-06-案卷12.md       结案报告：问句的推理、结论与证物，《传》可取材
  journal/2026-08-06.md            梦记（不超过五句）
~/.dozycat/store.db                小传 + 能量账本（Loro，跨端同步的那份）
```

分层的原则与 MOMENTS-PIPELINE 一致：notes 是原料，多、碎、永不同步；小传是成品，
每天至多三条，才进 CRDT 跨端。人物卡、链接卡、卷宗和梦记算 dream 与 searcher 的
工作记忆，也留在本机。⌥空格的搜索主要依赖这座花园：时间笔记、人物卡、链接卡、
小传先搜，凑不满一板证物才用 mdfind 翻本机文件补位。

## 行为上的纪律（实测踩出来的，别退化）

sequence 只写屏幕上看得见的事实，禁止想象动作、表情和心理活动；人名单独一行
「人物：」列出；同一分钟重跑要加秒后缀防覆盖；frontmatter 用本地时间——用 UTC
会让 dream 把下午误判成深夜。dream 先翻笔记再动手；人物卡是合并不是覆盖，旧证据
保留、新证据带日期；save_moment 宁缺毋滥，工具侧硬性卡在每天三条；笔记里没有的
不写。searcher 搜中文要用一两个字的短词、换着说法多试；回答不超过两句、必须带
出处；不脑补不编造；问句的判定放宽些——问号在句中、结尾的吗呢没、是不是有没有
记得，都算在问。链接卡只收真实存在的路径——路径是猜的不建卡，http/https 之外
的 scheme 不收。聊天里的 save_moment 由模型自主调用，存了也不打断对话去提。

## 隐私

屏幕 OCR 在本机（Vision）完成，截图用后即删；发给模型的只有白描和片段。notes、
people、journal 永不同步。测试时用 `DOZYCAT_FAKE_OCR` 注入假屏幕，真屏不出门。

## 自动化与测试的缝

环境变量：`DOZYCAT_LLM_KEY`（BYOK 注入）、`DOZYCAT_GARDEN`（花园根）、
`DOZYCAT_SEQ_SECS`（sequence 周期，默认 300）、`DOZYCAT_FAKE_OCR`、
`DOZYCAT_DEBUG_OUT`（searcher 的答案落文件）。debug 启动参数：
`-runSequence` / `-runDream` / `-searchQuery` / `-searchSubmit` / `-chatSend` /
`-demoReport`（无模型渲染结案报告）/ `-renderDelayMs`（截图前等动画走完）。

## 路线

pi 循环加三个 agent 加 agentic RAG 已经全线跑通（DeepSeek 实测）。接下来依次是：
pocket-pi 执行器替换（QuickJS，与 cat-poc 共享 runtime，行为定义不变）；笔记和
小传的本地向量化，补 grep 的召回，顺便让记事本 widget 能翻 notes；iOS 侧的
dream（HealthKit 加聊天记录，不观屏），睡前自动做梦加一条通知。

# dozycat 的 agent 体系

桌面和手机上的智能行为，不再是一次次零散的 LLM 调用，而是跑在 agent 执行器上。
执行器按平台分两档。桌面首选真 pi（`PiCLI.swift`）：pet 直接 spawn 本机的 `pi`
CLI，一片一片、找线索、聊天都用 pi 自带的 read/bash/edit/write 工具跑在花园目录
上，session 落在 `~/.pi/agent/sessions`（project 是 `~/.dozycat/garden`），打开
pi 的 session 浏览器就能看到「dozycat·一片一片」「dozycat·找线索」「dozycat·聊天」。
值得记的小事经 `moments_inbox.jsonl` 交接，由 pet 收件入库——store 的单写者
约定不破。没装 pi 的机器和 iOS 走内置循环（`PiAgent.swift`，OpenAI 兼容的
function calling），行为定义和 pi 档完全同构；面向上架的自包含运行时是
pocket-pi（QuickJS），到时候行为原样迁移。

## 原料层：一切笔记都能找回当时的原始输入

agent 之下还有一层不花钱的地基（`RawCapture.swift`）。OCR 是本机 Vision 模型、
零成本，所以节奏可以远快于模型调用：默认每 45 秒截一次**前台窗口**——像素经
ScreenCaptureKit 直接取进内存，**磁盘上从不出现截图文件**——OCR 带着位置信息
（boundingBox）出来。聊天应用（微信这类）按气泡的左右位置还原「谁说的什么」：
靠右的是我，靠左的是对方，居中短行降级为时间戳；连续同侧的行并成一条消息。
人和人说的原话，在这一层被一字不改地留住。

结构化的原料段去重后落 `raw/<日期>/<HHmmss>_raw.md`（屏幕没变不落重复，密码框
亮着或前台是懒猫自己时跳过），只留十四天——它是 cite 的地基，不是档案馆。
准确性要拿真窗口核：`open DozycatPet.app --args -ocrProbe /tmp/probe.md`，
再把微信点到前台，探针会把原始 OCR（带坐标）和聊天还原并排 dump 出来，肉眼
核对说话人归属和原话认没认对。节奏用 `DOZYCAT_RAW_SECS` 调（0 = 关）。

## 三个 agent，各管一段

**一段一段**（sequence）每五分钟跑一回：把这段时间原料层攒下的段子串起来，
连同前台 app、能量、久坐时长和劳动强度（intensity，键鼠折算的参与度）喂给
模型，白描两三句，只写可见的事实；原料里有人和人的对话时，加一节「对话摘录」
把最要紧的原话逐条留下（一字不改、注明说话人）。落成
`notes/<日期>/<HHmm>_note.md`，frontmatter 的 `sources:` 由代码落死、列出用到
的每份原料路径，正文每条事实标注（原料N）——**任何一条笔记都能找回当时的
原始输入**，这是硬保证，不依赖模型自觉。**一片一片**（dream）每十二次
一段一段或睡前跑一回：翻当天的笔记和已有的人物卡，搞清楚三件事——谁反复
出现、这段关系最近的温度、用户本人累不累答应过什么——更新 `people/<名>.md`，
证据优先引用笔记「对话摘录」里的原话、每条带出处（日期 + 笔记路径），用了哪
段笔记必须记得；往小传里存每天至多三条真正值得记住的小事（进 core，跨端
同步）；笔记里出现的、和用户有关的本机文件路径与网页链接，用 link_file /
link_url 留成 `links/<名>.md` 链接卡（花园是搜索的地基，值得再找到的东西都要
有一张卡）；最后写一篇不超过五句的梦记，末尾「取材：」列出实际用到的笔记。
**searcher** 在 ⌥空格
接到一句完整的问题时出动（agentic RAG）：拿着 search_moments、grep_notes、
read_note、人物卡、grep_links 和 mdfind 这些工具多轮翻找（花园里都没有才搜本机
文件），输出「推理：/结论：」两行——推理说线索怎么串起来的、出自哪，结论直接
回答。UI 把这两行渲染成结案报告（证物列清楚、盖「本猫断定」章），存档进
`cases/<日期>-案卷N.md`，《传》可取材。聊天在两端都一样：persona 加上最近的
小传当上下文，带一个 save_moment 工具，值得记的它自己存，闲聊不存。

## 数据地盘（全部本机、纯 markdown、用户可翻）

```
~/.dozycat/garden/
  raw/2026-08-08/110233_raw.md    原料段：前台窗口的高频 OCR（聊天带说话人），14 天自清
  notes/2026-08-06/1022_note.md   一段一段的时间笔记（frontmatter 带 sources cite 回原料）
  people/番薯.md                   人物卡：关系一句话、最近温度、带出处的证据（原话优先）
  links/番薯的合照.md              链接卡：target 指向本机文件或网页（frontmatter：target/date/why）
  cases/2026-08-06-案卷12.md       结案报告：问句的推理、结论与证物，《传》可取材
  journal/2026-08-06.md            梦记（不超过五句，末尾「取材」列用到的笔记）
~/.dozycat/store.db                小传 + 能量账本（Loro，跨端同步的那份）
```

分层的原则与 MOMENTS-PIPELINE 一致：raw 是原料的原料，最多最碎，只活十四天；
notes 是半成品，多、碎、永不同步；小传是成品，每天至多三条，才进 CRDT 跨端。
每一层都能 cite 回下一层：小传和人物卡的证据指到笔记，笔记的 sources 指到原料
——链路上任何一环都能追回当时屏幕上的原话。人物卡、链接卡、卷宗和梦记算
一片一片与 searcher 的工作记忆，也留在本机。⌥空格的搜索主要依赖这座花园：
时间笔记、人物卡、链接卡、小传先搜，凑不满一板证物才用 mdfind 翻本机文件补位。

## 行为上的纪律（实测踩出来的，别退化）

一段一段只写原料里看得见的事实，禁止想象动作、表情和心理活动；对话摘录里的
原话一字不改，说话人拿不准就不摘；每条事实标注（原料N），出处追不到的不写；
人名单独一行「人物：」列出；同一分钟重跑要加秒后缀防覆盖；frontmatter 用本地
时间——用 UTC 会让一片一片把下午误判成深夜。一片一片先翻笔记再动手；人物卡
是合并不是覆盖，旧证据保留、新证据带日期和笔记出处——用了哪段笔记必须记得；
save_moment 宁缺毋滥，工具侧硬性卡在每天三条；笔记里没有的不写。searcher 搜中文要用一两个字的短词、换着说法多试；回答不超过两句、必须带
出处；不脑补不编造；问句的判定放宽些——问号在句中、结尾的吗呢没、是不是有没有
记得，都算在问。链接卡只收真实存在的路径——路径是猜的不建卡，http/https 之外
的 scheme 不收。聊天里的 save_moment 由模型自主调用，存了也不打断对话去提。

## 隐私

屏幕像素经 ScreenCaptureKit 直接取进内存、OCR（本机 Vision）完即弃——磁盘上
从不出现截图文件；密码框亮着（secure input）或前台是懒猫自己时整拍跳过。发给
模型的只有原料文字段。raw、notes、people、journal 永不同步，raw 只留十四天。
权限在第一次见面时一页一页讲明白（`Onboarding.swift`）：要什么、为了什么、
代价是什么，用户点了「去授权」系统弹窗才出现——解释永远先于弹窗；感知也等
见完面才启动。设置的「感知」一节留着同样的说明，随时可查可关。
测试时用 `DOZYCAT_FAKE_OCR` 注入假屏幕，真屏不出门。

## 自动化与测试的缝

环境变量：`DOZYCAT_LLM_KEY`（BYOK 注入）、`DOZYCAT_GARDEN`（花园根）、
`DOZYCAT_SEQ_SECS`（一段一段周期，默认 300）、`DOZYCAT_RAW_SECS`（原料层
周期，默认 45，0 = 关）、`DOZYCAT_FAKE_OCR`、`DOZYCAT_DEBUG_OUT`（searcher
的答案落文件）。debug 启动参数：`-runSequence` / `-runDream` / `-searchQuery` /
`-searchSubmit` / `-chatSend` / `-demoReport`（无模型渲染结案报告）/
`-renderDelayMs`（截图前等动画走完）/ `-ocrProbe <路径>`（把目标窗口点到前台，
原始 OCR 和聊天还原并排 dump，核对准确性用）。

## 路线

pi 循环加三个 agent 加 agentic RAG 已经全线跑通（DeepSeek 实测）。接下来依次是：
pocket-pi 执行器替换（QuickJS，与 cat-poc 共享 runtime，行为定义不变）；笔记和
小传的本地向量化，补 grep 的召回，顺便让记事本 widget 能翻 notes；iOS 侧的
dream（HealthKit 加聊天记录，不观屏），睡前自动做梦加一条通知。

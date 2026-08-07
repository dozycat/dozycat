# 桌面 UI 的选型与手艺

这篇记录一次选型升级。起因是懒猫桌面端又丑又卡，而隔壁 ~/workspace/sheru 的
macOS 端流畅得基本就是原生应用。我们把它的源码深读了一遍——UI 层加 Services
约一万行全部通读——弄清流畅从哪来，然后照着把懒猫的壳层翻修了。结论先说：
不换框架，换分层。

## sheru 流畅的原因，不止「因为是 AppKit」

sheru 桌面端是纯 AppKit（NSViewController 体系）加 SwiftTerm 加 Rust core，
约一万七千行 Swift，没有 Electron，基本没有 SwiftUI，也没有 Combine 和
async/await——全是 GCD 加手写失效逻辑。但流畅感不是框架标签给的，读完的
体会是它几乎所有手法都是三条纪律的变体。

**第一条：绝不让用户看到一个两百毫秒后会变错的状态。** 可能阻塞的活儿全部
丢出主线程，回来时用单调递增的 generation 计数器判活——远程列目录每次
`apply()` 自增一个 `remoteLoadGeneration`，完成回调第一行就是「不是最新一代
就整个丢弃」（ContentViewController.swift:1179-1244）。取数期间旧列表留在
屏幕上；刷新失败时把先前的内容装回去、错误用 toast 说，面板永不清空——
它管这个叫 stale-while-error：「用户已经在读的那份列表，好过一个空面板」。

**第二条：瞬态 UI 过了阈值才显示，快路径永远不闪。** 加载浮层排在一个 120ms
后才执行的 DispatchWorkItem 里，取数先回来就取消它（:1196-1210）；文件操作的
进度 sheet 阈值是 500ms。注释写得直白：缓存命中应当感觉是同步的。这是全库
最便宜的去卡顿手段。

**第三条：动画做在窗口层，由 Core Animation 合成。** 全应用只有四处动画，
都在 0.15 到 0.25 秒之间：终端面板滑入、状态栏折叠、toast 淡入淡出、侧栏
折叠。全部走 `NSAnimationContext.runAnimationGroup` 配
`constraint.animator()`，GPU 上合成，内容一个像素不重画。更值得记的是有两处
**刻意取消**了动画：隐藏动画会和同一次刷新触发的重排竞速、在原处留一道空缝，
就直接扁平折叠；新窗口恢复「记忆中已打开」的终端时完全跳过滑入，「面板就是
单纯地已经在那儿了」。分段揭示在用户第二次看到时就读作慢——SwiftUI 的
`withAnimation` 每帧重新求值 body，同样一个「面板落下来」，成本差一个量级。

列表层面的纪律与此同构：view-based 表格、`makeView(withIdentifier:)` 复用、
显式固定行高（`usesAutomaticRowHeights = false`），流式结果用
`insertRows(at:withAnimation:)` 增量进表，单行变化用
`reloadData(forRowIndexes:)`，永不整表 reload。必须整表 reload 的地方（本地
文件变更）包在一套捕获-恢复里：展开边界和滚动原点按**值身份**重新匹配（node
对象从不跨 reload 存活），选中按名字保，first-responder 只在浏览器本来就持有
焦点时才恢复——「不要去抢别处的焦点，只是保住它」
（FileBrowserViewController.swift:38-51、ContentViewController.swift:668-714）。

浮动面板有一套标准做法，GoToFolderPanel.swift 整篇是教科书：borderless
NSPanel 子类 override `canBecomeKey`（无边框面板默认拿不到 key）；
`NSVisualEffectView`（behindWindow）打底，圆角必须用 **maskImage** 裁——layer
的 cornerRadius 裁不掉窗后模糊；挂成父窗的 child window 跟着走；
`didResignKeyNotification` 一失焦立即收起，点别处自动消失；补全列表增减时
`setFrameTopLeftPoint` 锚住顶边调高度，输入框纹丝不动。键盘语义放在
responder chain 里而不是全局事件监听：输入框的
`control(_:textView:doCommandBy:)` 接管上下箭头、Tab、回车、Esc，表格子类
override `keyDown`，行为只在自己是 first responder 时生效；面板还得在
`performKeyEquivalent` 里主动认领自己要的键（⌘⌫），否则会穿透到主菜单的
Move to Trash 上去。

观感上的省力秘诀是语义色加系统控件：`.labelColor`、`.secondaryLabelColor`、
recessed 按钮、`.inset` 表格——原生观感白送，暗色模式自动成立，所以整个外观
管理只有 41 行，核心一行 `NSApp.appearance`（Appearance.swift:34），在任何
窗口存在之前应用，第一个窗口就画对。唯二不会自动跟随的地方（缓存了 CGColor
的 layer、第三方缓存色）拿到显式的 `viewDidChangeEffectiveAppearance` 覆写——
这是条好用的通则。

## 我们的选型：混合，不全盘重写

懒猫桌面端此前是 SwiftUI 视图装在自制 FloatingPanel（NSPanel +
NSHostingView）里。对着 sheru 逐面审计下来，丑和卡的根源几乎都在壳层和几处
架构失误，不在 SwiftUI 本身：面板每次 toggle 新建、尺寸一次定死、没有失焦
收起（esc 靠全局 event monitor 兜底）、没有 vibrancy、整套 DS 色板只有亮色
硬编码 hex、面板出现没有窗口层动画、还在 `.nonactivatingPanel` 上调
`NSApp.activate` 自相矛盾地抢前台；内容层则有能量面板在 body 里同步读盘、
搜索面板用 `.id()` 每次炸掉整棵子树这样的自伤。

所以选型结论是**混合**：壳层——窗口、材质、进出场动画、键盘、失焦语义——
下沉到 AppKit，按 sheru 的做法写；内容层继续 SwiftUI。猫脸、卡片这些品牌
视觉件和 iOS 共享（CatFace / DS），全盘 AppKit 重写会把这份共享扔掉，换不回
等值的收益。sheru 自己也验证了这个思路的另一半：它的 web 引擎窗口照样能做到
不「网页般迟钝」，靠的是壳层手艺（预热、occlusion 处理、首帧对齐），而不是
渲染技术本身。

## 已落地的改动

**CardPanel（Sources/CardPanel.swift）**，FloatingPanel 的换代，搜索、对话、
能量、《传》四个面板共用。borderless 加 nonactivating，override
`canBecomeKey`——像 Spotlight 一样拿键盘但不抢激活，唤起收起不再引发前台
app 的切换闪动；`NSVisualEffectView`（popover 材质，behindWindow）打底，
maskImage 裁圆角，各面板的根背景从不透明纸面改成半透明
（`DS.paper.opacity(0.82)`）罩在真模糊上；失焦自动收起，和 esc、显式关闭走
同一条 `dismiss()` 路，全局 esc 监听删掉，esc 由 `cancelOperation` 在
responder chain 里兜底；进出场在窗口层做 alpha 加位移（`animator()`），
SearchPanel 内容层原来的 landed spring 删掉，不再双重动画；`showCentered`
和 `show(near:)` 都把 origin 夹进 visibleFrame，小屏上 900pt 宽的能量面板
不会掉出屏幕；`resizeToFitKeepingTop()` 备好了顶边锚定的动画调高，日后做
动态高度用。

**DS 动态色（apps/ios/Dozycat/DesignSystem/DS.swift）**。中性色全部换成
`Color(light:dark:)` 双值动态色，macOS 走 NSColor dynamic provider，iOS 暂锁
亮色不受影响。暗色档从设计稿的 night 系推出：纸面变墨面、墨字反白，coral 和
blue 点缀色两种外观通用。猫的固有色单列成 `catInk` / `catLine`——脸永远是
白的，五官不随外观反色；同理《传》的书脊定性为深色书皮的固有色（DS.night），
暗色下不再反白成一条亮带。新增 `card` 层级色给证物板的卡片和日历格子。外观
切换进了设置（跟随系统 / 亮 / 暗），`PetAppDelegate.applyAppearancePreference`
一行 `NSApp.appearance` 全局立即生效，做法同 sheru 的 AppearanceManager。

**卡顿源对着审计清单逐个拔。** 能量面板原来在 body 里同步读盘——`movers`
每次求值翻整天的 note 目录逐文件读，K 线分桶、月历均值在主线程重复解析，
sense 每分钟一个 tick 全部重来；现在采样、蜡烛、app 标注统一在 `reload()`
的 `Task.detached` 里备好存 @State，body 零 IO。证物板原来
`.id(searchGeneration)` 每次搜索销毁重建整棵子树，1.5 秒的钉卡级联从头重播，
连续打字等于动画永远在开场；现在 ForEach 按证物 id diff，留下来的卡不重播，
只有新卡落钉，红线单独重牵并收紧到 0.55s。忙碌指示学 sheru 的阈值延迟：
防抖期不算在搜，spinner 满 150ms 才现身。桌宠的呼吸动画作用在一棵带三层
离屏阴影的形状树上，每帧重新光栅化；`.drawingGroup()` 压成单张纹理后动画只
变换纹理，顺手修掉一个真 bug——呼吸挂在 onAppear 上，心情切到睡着或没电再
回来就永远停摆，改成 `.task(id: breathes)` 跟随状态重启。搜索的主线程磁盘 IO
也清了：mdfind 命中的修改时间在后台队列取好随 FileHit 带回，空状态的
「未结的案子」目录枚举挪进 `Task.detached`，面板唤起第一帧不碰磁盘。

**观感杂修。** 菜单栏下拉不再铺不透明纸底，让 popover 材质自己透出来，动作行
补上 hover 反馈——原生菜单的最低礼仪；证物卡的选中描边不再和「最新」描边
同时命中两张卡。

验证方式：Debug 构建加 `-renderPanels` 无头渲染，亮暗各出一套 PNG 逐面核对
（外观用 `-uiAppearance dark` 启动参数覆盖）。

## 还没做、按价值排序

搜索的四个后台工作器（notes、people、links、mdfind）还没有取消检查，
`searchTask?.cancel()` 停不掉已经起飞的活，快打十个字就是几十个白干的阻塞
线程加十个 mdfind 进程——照 sheru Search.swift 的做法加取消 token，在派发前、
阻塞调用后、主线程 hop 三个点位检查。SearchModel 该迁 `@Observable`
（macOS 14 就有）：现在 query 的 didSet 连着改四五个 @Published，
@ObservedObject 观察整个对象，一次按键好几轮全量 body 失效，逐属性追踪基本
白送。证物板和结案报告可以做动态高度：内容变化时 `resizeToFitKeepingTop()`，
像 Finder 前往文件夹那样面板长短随内容走。对话输入框包一个 NSTextView 支持
多行和 shift+enter；聊天列表规模大了以后参考 sheru 的捕获-恢复纪律。面板在
静止光标下出现时 hover 态会卡住（enter/exit 不触发），sheru 的解法是
updateTrackingAreas 里对齐 `mouseLocationOutsideOfEventStream`，SwiftUI 下
需要一个 NSViewRepresentable 垫片。

两个设计取舍留给番薯拍板：其一，审计对「证物板」隐喻本身有异议——固定槽位
的旋转卡片既是卡顿源也不像搜索结果，红线会从卡片脸上穿过去，建议换普通竖排
结果列表，但这是产品味道的取舍不是纯技术判断；其二，设置窗要不要改标准
`Form.grouped`——现在的手绘风是设计语言的一部分，但设置恰是用户最期待系统
chrome 的地方。最后，iOS 侧放开 `Color(light:dark:)` 的暗色档，连同一次真正
的暗色设计走查。

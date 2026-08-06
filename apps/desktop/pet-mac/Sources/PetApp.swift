import SwiftUI
import Carbon.HIToolbox

@main
struct DozycatPetApp: App {
    @NSApplicationDelegateAdaptor(PetAppDelegate.self) private var delegate
    @ObservedObject private var feed = SenseFeed.shared

    init() {
        Self.applyLanguagePreference()
    }

    /// 界面语言：默认中文；设置里可切「跟随系统 / 中文 / EN」（重启生效）。
    /// 必须在任何字符串被解析前调用（App.init 最早）。
    static func applyLanguagePreference() {
        switch UserDefaults.standard.string(forKey: "uiLanguage") ?? "zh" {
        case "zh": UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case "en": UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        default: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    var body: some Scene {
        // 菜单栏下拉 · 数字的第二个家（设计稿「菜单栏下拉」）
        MenuBarExtra {
            MenuBarDropdown()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cat.fill")
                    .accessibilityLabel("懒猫")
                Text(verbatim: feed.phys.formatted(.percent))
            }
            .accessibilityElement(children: .combine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PetSettingsView()
        }
    }
}

/// 菜单栏下拉：能量对 + 三个动作行（休息 / 搜索 / 下一个提醒）。
struct MenuBarDropdown: View {
    @ObservedObject private var feed = SenseFeed.shared
    @ObservedObject private var bio = BiographyStore.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            // 点数字进能量 widgets：日历、K 线、回血清单、明日计划
            Button {
                PetPanels.shared.toggleEnergy()
            } label: {
                HStack(spacing: 0) {
                    energyCell("心理", value: feed.mind, color: DS.blue, warn: false)
                    DS.line.frame(width: 1).padding(.horizontal, 14)
                    energyCell("生理", value: feed.phys, color: DS.coral, warn: feed.phys < 50)
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("能量日历与今天的走势")

            VStack(spacing: 0) {
                actionRow("休息 5 分钟", shortcut: "⌥R") { PetPanels.shared.startRest() }
                DS.lineSoft.frame(height: 1)
                actionRow("找点什么 / 问问回忆", shortcut: "⌥␣") { PetPanels.shared.toggleSearch() }
                DS.lineSoft.frame(height: 1)
                actionRow("能量 · 日历与 K 线", shortcut: "⌥E") { PetPanels.shared.toggleEnergy() }
                DS.lineSoft.frame(height: 1)
                actionRow(bookRowLabel, shortcut: "") { PetPanels.shared.toggleBook() }
                DS.lineSoft.frame(height: 1)
                HStack {
                    Text("下一个提醒 · 傍晚散步").font(.system(size: 13)).foregroundStyle(DS.ink)
                    Spacer()
                    Text(verbatim: "18:30").font(.system(size: 13)).foregroundStyle(DS.faint)
                }
                .padding(.vertical, 11).padding(.horizontal, 2)
            }
            .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }

            HStack {
                Button("设置…") { openSettings(); NSApp.activate(ignoringOtherApps: true) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(DS.muted)
                Spacer()
                Button("退出懒猫") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(DS.muted)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 300)
        .background(DS.paper)
    }

    private var bookRowLabel: LocalizedStringKey {
        if let latest = bio.latest {
            return "传 · 第\(ChineseNumeral.ordinal(latest.index))回《\(latest.title)》"
        }
        return "传 · 还没开笔"
    }

    private func energyCell(_ label: LocalizedStringKey, value: Int, color: Color, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10)).tracking(2).foregroundStyle(DS.muted)
            Text("\(value)")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(warn ? color : DS.ink)
            GeometryReader { geo in
                Capsule().fill(DS.bg)
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .frame(width: geo.size.width * CGFloat(min(max(value, 0), 100)) / 100)
                    }
            }
            .frame(height: 3)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionRow(_ label: LocalizedStringKey, shortcut: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(DS.ink)
                Spacer()
                Text(verbatim: shortcut).font(.system(size: 13)).foregroundStyle(DS.faint)
            }
            .padding(.vertical, 11).padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 面板管理：Search Everything、对话、能量 widgets 与休息倒计时。
@MainActor
final class PetPanels {
    static let shared = PetPanels()

    /// 桌宠窗——对话面板往猫旁边靠时用它定位。
    weak var petWindow: NSWindow?

    private var searchPanel: NSPanel?
    private var chatPanel: NSPanel?
    private var energyPanel: NSPanel?
    private var bookPanel: NSPanel?
    private lazy var escMonitor: Any? = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard event.keyCode == 53, let self else { return event } // esc
        if self.searchVisible { self.closeSearch(); return nil }
        if self.energyVisible { self.closeEnergy(); return nil }
        if self.bookVisible { self.closeBook(); return nil }
        if self.chatVisible { self.closeChat(); return nil }
        return event
    }

    func toggleSearch() {
        if searchVisible {
            closeSearch()
            return
        }
        _ = escMonitor
        let panel = FloatingPanel(content: SearchPanelView(), width: 640)
        searchPanel = panel
        SenseFeed.shared.panelsOpen = true
        panel.showCentered()
    }

    private var searchVisible: Bool { searchPanel?.isVisible ?? false }

    func closeSearch() {
        searchPanel?.orderOut(nil)
        searchPanel = nil
        syncPanelMood()
    }

    /// 对话 · 点猫猫展开（设计稿「对话」）。
    func toggleChat() {
        if chatVisible {
            closeChat()
            return
        }
        _ = escMonitor
        let panel = FloatingPanel(content: ChatPanelView(), width: 380)
        chatPanel = panel
        SenseFeed.shared.panelsOpen = true
        panel.show(near: petWindow)
    }

    private var chatVisible: Bool { chatPanel?.isVisible ?? false }

    func closeChat() {
        chatPanel?.orderOut(nil)
        chatPanel = nil
        syncPanelMood()
    }

    /// 能量 widgets：日历、K 线、回血清单、明日计划（设计稿「能量 WIDGETS」）。
    func toggleEnergy() {
        if energyVisible {
            closeEnergy()
            return
        }
        _ = escMonitor
        RechargeStore.shared.refreshRecommendation()
        let panel = FloatingPanel(content: EnergyPanelView(), width: 900)
        energyPanel = panel
        SenseFeed.shared.panelsOpen = true
        panel.showCentered(yRatio: 0.54)
    }

    private var energyVisible: Bool { energyPanel?.isVisible ?? false }

    func closeEnergy() {
        energyPanel?.orderOut(nil)
        energyPanel = nil
        syncPanelMood()
    }

    /// 《传》——正文书页（书脊上的「传」印切目录）。
    func toggleBook() {
        if bookVisible {
            closeBook()
            return
        }
        _ = escMonitor
        let panel = FloatingPanel(content: BookPanelView(), width: 760)
        bookPanel = panel
        SenseFeed.shared.panelsOpen = true
        panel.showCentered(yRatio: 0.56)
    }

    private var bookVisible: Bool { bookPanel?.isVisible ?? false }

    func closeBook() {
        bookPanel?.orderOut(nil)
        bookPanel = nil
        syncPanelMood()
    }

    private func syncPanelMood() {
        SenseFeed.shared.panelsOpen = searchVisible || chatVisible || energyVisible || bookVisible
    }

    #if DEBUG
    /// 调试：8 态猫猫总览（对齐设计稿「猫猫状态」）。
    func showMoodBoard() {
        let moods: [(CatMood, LocalizedStringKey)] = [
            (.doze, "打盹 · 默认"), (.asleep, "睡着了"), (.happy, "开心"), (.curious, "好奇"),
            (.worried, "担心你"), (.drained, "没电了"), (.breathing, "陪你呼吸"), (.missYou, "想你了"),
        ]
        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(180)), count: 4), spacing: 24) {
            ForEach(Array(moods.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 12) {
                    DeskCat(mood: item.0)
                    Text(item.1).font(.system(size: 13, weight: .medium)).foregroundStyle(DS.ink)
                }
                .frame(width: 180, height: 170)
                .background(RoundedRectangle(cornerRadius: 20).fill(DS.paper))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(DS.line, lineWidth: 1))
            }
        }
        .padding(28)
        .background(DS.bg)
        let panel = FloatingPanel(content: grid, width: 900)
        searchPanel = panel
        panel.showCentered(yRatio: 0.5)
    }
    #endif

    /// 休息 5 分钟：给猫放个假（提醒卡显示倒计时结束语）。
    func startRest() {
        SenseFeed.shared.acknowledgeReminder()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            SenseFeed.shared.reminderCount += 1
        }
    }
}

/// 透明、置顶、可拖动的桌宠窗口。
final class PetAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var hotKeys: [HotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let hosting = NSHostingView(rootView: PetView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.maxX - 460, y: frame.minY + 40))
        }
        window.orderFrontRegardless()
        self.window = window
        PetPanels.shared.petWindow = window
        // 全局快捷键：⌥空格 = Search Everything，⌥R = 休息
        hotKeys.append(HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) {
            PetPanels.shared.toggleSearch()
        })
        hotKeys.append(HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey)) {
            PetPanels.shared.startRest()
        })
        hotKeys.append(HotKey(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(optionKey)) {
            PetPanels.shared.toggleEnergy()
        })

        SenseFeed.shared.start()
        startAgents()
        // 《传》：启动后看看是不是该写了（月初定稿上一回 / 本月开新的一回）
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            BiographyStore.shared.tickIfNeeded()
        }

        #if DEBUG
        // 历史迁移（放 delegate 里：锁屏时窗口不 appear，不能挂在 onAppear 上）
        if let path = UserDefaults.standard.string(forKey: "importMoments") {
            let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            var count = 0
            for line in raw.split(separator: "\n") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                    as? [String: Any],
                    let text = obj["text"] as? String, !text.isEmpty else { continue }
                let atMs = (obj["atMs"] as? Double).map(Int64.init)
                    ?? (obj["date"] as? String)
                        .flatMap { day.date(from: $0) }
                        .map { Int64($0.timeIntervalSince1970 * 1000 + 12 * 3600 * 1000) }
                guard let atMs else { continue }
                PetStore.shared.importMemory(atMs: atMs, text: text, note: obj["note"] as? String)
                count += 1
            }
            MomentsBridge.writeSnapshot()
            NSLog("importMoments: %d from %@", count, path)
        }
        // 历史章节补写：给每个有素材、没有章的月份定稿一回
        if UserDefaults.standard.bool(forKey: "backfillBiography") {
            Task { @MainActor in
                await BiographyStore.shared.backfillHistory()
            }
        }
        #endif
    }

    /// sequence agent 定时跑（默认 5 分钟），每 12 次 sequence 后做一次梦。
    private func startAgents() {
        let seqSecs = UInt64(ProcessInfo.processInfo.environment["DOZYCAT_SEQ_SECS"]
            .flatMap(UInt64.init) ?? 300)
        Task { @MainActor in
            var runs = 0
            while true {
                try? await Task.sleep(nanoseconds: seqSecs * 1_000_000_000)
                // 人不在就不记（省 token 也省隐私）：上一分钟无输入即视为空闲
                guard SenseFeed.shared.activeStreakMin > 0 else { continue }
                _ = await SequenceAgent.run()
                runs += 1
                if runs % 12 == 0 {
                    NSLog("DreamAgent: %@", await DreamAgent.run())
                    BiographyStore.shared.tickIfNeeded()
                }
            }
        }
    }
}

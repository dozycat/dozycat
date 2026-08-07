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
                .padding(.vertical, 11).padding(.horizontal, 8)
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
        // 不铺不透明纸底：让 MenuBarExtra 的 popover 材质自己透出来
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
        MenuActionRow(label: label, shortcut: shortcut, action: action)
    }
}

/// 菜单动作行：悬停有底色反馈——原生菜单的最低礼仪。
private struct MenuActionRow: View {
    let label: LocalizedStringKey
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).font(.system(size: 13)).foregroundStyle(DS.ink)
                Spacer()
                Text(verbatim: shortcut).font(.system(size: 13)).foregroundStyle(DS.faint)
            }
            .padding(.vertical, 11).padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? DS.lineSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 面板管理：Search Everything、对话、能量 widgets 与休息倒计时。
@MainActor
final class PetPanels {
    static let shared = PetPanels()

    /// 桌宠窗——对话面板往猫旁边靠时用它定位。
    weak var petWindow: NSWindow?

    private var searchPanel: CardPanel?
    private var chatPanel: CardPanel?
    private var energyPanel: CardPanel?
    private var bookPanel: CardPanel?

    /// 面板收起后的收尾统一走 CardPanel.onClose（esc、失焦、显式 close 同一条路）。
    private func adopt(_ panel: CardPanel, into slot: ReferenceWritableKeyPath<PetPanels, CardPanel?>) {
        self[keyPath: slot] = panel
        SenseFeed.shared.panelsOpen = true
        panel.onClose = { [weak self] in
            guard let self, self[keyPath: slot] === panel else { return }
            self[keyPath: slot] = nil
            self.syncPanelMood()
        }
    }

    func toggleSearch() {
        if searchVisible {
            closeSearch()
            return
        }
        let panel = CardPanel(content: SearchPanelView(), width: 640)
        adopt(panel, into: \.searchPanel)
        panel.showCentered()
    }

    private var searchVisible: Bool { searchPanel?.isVisible ?? false }

    func closeSearch() {
        searchPanel?.dismiss()
    }

    /// 对话 · 点猫猫展开（设计稿「对话」）。
    func toggleChat() {
        if chatVisible {
            closeChat()
            return
        }
        let panel = CardPanel(content: ChatPanelView(), width: 380, cornerRadius: 20)
        adopt(panel, into: \.chatPanel)
        panel.show(near: petWindow)
    }

    private var chatVisible: Bool { chatPanel?.isVisible ?? false }

    func closeChat() {
        chatPanel?.dismiss()
    }

    /// 能量 widgets：日历、K 线、回血清单、明日计划（设计稿「能量 WIDGETS」）。
    func toggleEnergy() {
        if energyVisible {
            closeEnergy()
            return
        }
        RechargeStore.shared.refreshRecommendation()
        let panel = CardPanel(content: EnergyPanelView(), width: 900, cornerRadius: 24)
        adopt(panel, into: \.energyPanel)
        panel.showCentered(yRatio: 0.54)
    }

    private var energyVisible: Bool { energyPanel?.isVisible ?? false }

    func closeEnergy() {
        energyPanel?.dismiss()
    }

    /// 《传》——正文书页（书脊上的「传」印切目录）。
    func toggleBook() {
        if bookVisible {
            closeBook()
            return
        }
        let panel = CardPanel(content: BookPanelView(), width: 760, cornerRadius: 20)
        adopt(panel, into: \.bookPanel)
        panel.showCentered(yRatio: 0.56)
    }

    private var bookVisible: Bool { bookPanel?.isVisible ?? false }

    func closeBook() {
        bookPanel?.dismiss()
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
        let panel = CardPanel(content: grid, width: 900)
        adopt(panel, into: \.searchPanel)
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
        Self.applyAppearancePreference()

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
        SenseHintsPump.shared.start()
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

    /// 外观：默认跟系统；设置里可锁「亮 / 暗」。一行 NSApp.appearance 全局生效，
    /// DS 的动态色和 CardPanel 的 vibrancy 都会跟着走（做法同 sheru AppearanceManager）。
    static func applyAppearancePreference() {
        switch UserDefaults.standard.string(forKey: "uiAppearance") ?? "system" {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
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

import SwiftUI
import Carbon.HIToolbox

@main
struct DozycatPetApp: App {
    @NSApplicationDelegateAdaptor(PetAppDelegate.self) private var delegate
    @ObservedObject private var feed = SenseFeed.shared

    var body: some Scene {
        // 菜单栏下拉 · 数字的第二个家（设计稿「菜单栏下拉」）
        MenuBarExtra {
            MenuBarDropdown()
        } label: {
            Text("懒猫 \(feed.phys.formatted(.percent))")
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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                energyCell("心理", value: feed.mind, color: DS.blue, warn: false)
                DS.line.frame(width: 1).padding(.horizontal, 14)
                energyCell("生理", value: feed.phys, color: DS.coral, warn: feed.phys < 50)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                actionRow("休息 5 分钟", shortcut: "⌥R") { PetPanels.shared.startRest() }
                DS.lineSoft.frame(height: 1)
                actionRow("找点什么 / 问问回忆", shortcut: "⌥␣") { PetPanels.shared.toggleSearch() }
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

/// 面板管理：对话 widget、Search Everything、休息倒计时。
@MainActor
final class PetPanels {
    static let shared = PetPanels()

    var petWindow: NSWindow?
    private var chatPanel: NSPanel?
    private var searchPanel: NSPanel?
    private lazy var escMonitor: Any? = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        if event.keyCode == 53 { // esc
            self?.closeSearch()
            self?.closeChat()
            return nil
        }
        return event
    }

    func toggleChat() {
        if let panel = chatPanel, panel.isVisible {
            closeChat()
            return
        }
        _ = escMonitor
        let panel = FloatingPanel(
            content: ChatWidget { [weak self] in self?.closeChat() },
            width: 380
        )
        chatPanel = panel
        SenseFeed.shared.panelsOpen = true
        panel.showAbove(window: petWindow, offset: NSPoint(x: -20, y: -110))
    }

    func closeChat() {
        chatPanel?.orderOut(nil)
        chatPanel = nil
        SenseFeed.shared.panelsOpen = searchVisible
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
        SenseFeed.shared.panelsOpen = false
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

        SenseFeed.shared.start()
        startAgents()
    }

    /// sequence agent 定时跑（默认 5 分钟），每 12 次 sequence 后做一次梦。
    private func startAgents() {
        let seqSecs = UInt64(ProcessInfo.processInfo.environment["DOZYCAT_SEQ_SECS"]
            .flatMap(UInt64.init) ?? 300)
        Task { @MainActor in
            var runs = 0
            while true {
                try? await Task.sleep(nanoseconds: seqSecs * 1_000_000_000)
                _ = await SequenceAgent.run()
                runs += 1
                if runs % 12 == 0 {
                    NSLog("DreamAgent: %@", await DreamAgent.run())
                }
            }
        }
    }
}

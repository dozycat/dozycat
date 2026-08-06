import SwiftUI

/// 桌宠本体：提醒卡 + 悬停能量胶囊 + 会换表情的猫（桌面套件）。
/// 原则：猫本身就是能量表——数字只在悬停时出现。
struct PetView: View {
    @ObservedObject private var feed = SenseFeed.shared
    @ObservedObject private var bio = BiographyStore.shared
    @Environment(\.openSettings) private var openSettings
    @State private var hovering = false
    @State private var hoverDismissTask: Task<Void, Never>?
    #if DEBUG
    @State private var debugHoverLocked = false
    #endif

    var body: some View {
        content
            .onAppear {
                #if DEBUG
                let defaults = UserDefaults.standard
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if defaults.bool(forKey: "showSettings") {
                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()
                    }
                    if defaults.bool(forKey: "showSearch") { PetPanels.shared.toggleSearch() }
                    if let q = defaults.string(forKey: "searchQuery") {
                        SearchModel.shared.query = q
                    }
                    if defaults.bool(forKey: "demoHover") {
                        hovering = true
                        debugHoverLocked = true
                    }
                    if defaults.bool(forKey: "showMoods") { PetPanels.shared.showMoodBoard() }
                    if defaults.bool(forKey: "showChat") { PetPanels.shared.toggleChat() }
                    if defaults.bool(forKey: "showEnergy") { PetPanels.shared.toggleEnergy() }
                    if defaults.bool(forKey: "showBook") { PetPanels.shared.toggleBook() }
                    if defaults.bool(forKey: "demoChat") {
                        ChatModel.shared.messages = [
                            ChatMsg(role: .me, text: "好烦，方案又被打回来了", memoryRef: nil),
                            ChatMsg(role: .cat,
                                    text: "第三稿了对吧，换谁都会烦的。先不想它——你从中午到现在还没喝过水，去接一杯，回来要是还想说，我在。",
                                    memoryRef: "它记下了：这个项目最近让你很耗"),
                        ]
                    }
                    // 无头渲染面板到 PNG（锁屏/CI 下也能核对视觉）
                    if let dir = defaults.string(forKey: "renderPanels") {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            var panels: [(String, AnyView)] = [
                                ("chat", AnyView(ChatPanelView())),
                                ("energy", AnyView(EnergyPanelView())),
                                ("book", AnyView(BookPanelView())),
                                ("search", AnyView(SearchPanelView())),
                                ("pet", AnyView(
                                    VStack(alignment: .trailing, spacing: 0) {
                                        EnergyCapsule()
                                        DeskCat(mood: .doze, size: 110)
                                            .padding(.trailing, 24)
                                    }
                                    .padding(36)
                                )),
                                ("moods", AnyView(MoodBoardGrid())),
                            ]
                            if let chapter = BiographyStore.shared.news {
                                panels.append(("booknews", AnyView(BookNewsCard(chapter: chapter))))
                            }
                            for (name, view) in panels {
                                // 没有窗口的视图 layer contentsScale 是 1x，文字先按 1x
                                // 光栅化再放大必然发虚——挂进一个全透明、垫底的真窗口，
                                // 让图层拿到屏幕的 Retina backing scale 再截。
                                let host = NSHostingView(rootView: view)
                                let size = host.fittingSize
                                host.frame = NSRect(origin: .zero, size: size)
                                let window = NSWindow(
                                    contentRect: NSRect(origin: .zero, size: size),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
                                window.isOpaque = false
                                window.backgroundColor = .clear
                                window.alphaValue = 0        // 用户看不见，内容照常光栅化
                                window.ignoresMouseEvents = true
                                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
                                window.contentView = host
                                window.orderBack(nil)
                                try? await Task.sleep(nanoseconds: 400_000_000) // 等布局与 2x 重光栅化
                                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
                                else { window.orderOut(nil); continue }
                                host.cacheDisplay(in: host.bounds, to: rep)
                                window.orderOut(nil)
                                if let png = rep.representation(using: .png, properties: [:]) {
                                    try? png.write(to: URL(fileURLWithPath: dir)
                                        .appendingPathComponent("\(name).png"))
                                }
                            }
                            NSLog("renderPanels: done")
                        }
                    }
                    if defaults.bool(forKey: "searchSubmit") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            SearchModel.shared.submit()
                        }
                    }
                    if defaults.bool(forKey: "runSequence") {
                        Task { _ = await SequenceAgent.run() }
                    }
                    if defaults.bool(forKey: "runDream") {
                        Task { NSLog("DreamAgent: %@", await DreamAgent.run()) }
                    }
                }
                #endif
            }
    }

    private var content: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Spacer(minLength: 0)

            if let reminder = feed.reminder {
                ReminderCard(
                    message: reminder,
                    countLine: String(localized: "今天第 \(feed.reminderCount) 次提醒 · 你答应过自己的"),
                    onGo: { feed.acknowledgeReminder() },
                    onSnooze: { feed.snoozeReminder() }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let chapter = bio.news {
                // 《传》更新那天，它把新的一回递给你（提醒卡优先）
                BookNewsCard(chapter: chapter)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 固定占位尺寸：EnergyCapsule 出现前后都不参与重新测量，猫不会横移。
            ZStack(alignment: .bottomTrailing) {
                if hovering && feed.reminder == nil {
                    EnergyCapsule()
                        .offset(y: -108)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)),
                            removal: .opacity
                        ))
                        .onHover { setHovering($0) }
                        .zIndex(1)
                }
                DeskCat(mood: feed.mood, size: 110)
                    .onHover { setHovering($0) }
                    // 点猫猫展开对话（设计稿「对话」）
                    .onTapGesture { PetPanels.shared.toggleChat() }
            }
            .frame(width: 230, height: 230, alignment: .bottomTrailing)
            .padding(.trailing, 20)
        }
        .padding(20)
        .frame(width: 420, height: 420, alignment: .bottomTrailing)
        .animation(.easeOut(duration: 0.25), value: feed.reminder)
    }

    /// 鼠标从猫移到能量卡时会短暂经过连接线；延迟收起可消除边界闪烁。
    private func setHovering(_ inside: Bool) {
        #if DEBUG
        if debugHoverLocked {
            hovering = true
            return
        }
        #endif
        hoverDismissTask?.cancel()
        if inside {
            withAnimation(.easeOut(duration: 0.16)) { hovering = true }
            return
        }
        hoverDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.14)) { hovering = false }
        }
    }
}

#if DEBUG
/// 8 态猫猫总览（调试 / 官网截图用）。
struct MoodBoardGrid: View {
    private let moods: [(CatMood, LocalizedStringKey)] = [
        (.doze, "打盹 · 默认"), (.asleep, "睡着了"), (.happy, "开心"), (.curious, "好奇"),
        (.worried, "担心你"), (.drained, "没电了"), (.breathing, "陪你呼吸"), (.missYou, "想你了"),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(180)), count: 4), spacing: 24) {
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
    }
}
#endif

#Preview {
    PetView()
}

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
                    if let path = defaults.string(forKey: "captureSearch") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            PetPanels.shared.writeSearchSnapshot(to: path)
                        }
                    }
                    if let path = defaults.string(forKey: "capturePet") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            NSApp.windows.first(where: {
                                abs($0.frame.width - 420) < 1 && abs($0.frame.height - 420) < 1
                            })?.contentView?.writeDebugPNG(to: path)
                        }
                    }
                    if let q = defaults.string(forKey: "searchQuery") {
                        SearchModel.shared.query = q
                    }
                    if defaults.bool(forKey: "demoHover") {
                        hovering = true
                        debugHoverLocked = true
                    }
                    if defaults.bool(forKey: "showMoods") { PetPanels.shared.showMoodBoard() }
                    if defaults.bool(forKey: "showNotes") { PetPanels.shared.toggleNotes() }
                    if defaults.bool(forKey: "showBook") { PetPanels.shared.toggleBook() }
                    if defaults.bool(forKey: "demoReport") {
                        SearchModel.shared.query = "上次牙疼是什么时候来着？"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            SearchModel.shared.caseReport = .init(
                                seq: 11, title: "智齿",
                                reasoning: "五月十四日疼过一次（A），医嘱要拔（B）。此后 81 天，你再没提过牙——不是好了，是拖着。",
                                conclusion: "上次牙疼是 **5月14日**，距今 84 天。智齿还在，复查欠着。要不要我下周替你把这个案子了结？",
                                sources: [
                                    .init(id: "d1", text: "「右边智齿疼得没睡好」",
                                          source: "5月14日 · 倾诉", note: nil, at: Date()),
                                    .init(id: "d2", text: "「医生建议拔，我说缓缓再说」",
                                          source: "5月17日 · 倾诉", note: nil, at: Date()),
                                    .init(id: "d3", text: "口腔全景片-0517.pdf",
                                          source: "~/文档/体检", note: nil, at: Date()),
                                ],
                                duration: 0.4, fileURL: nil)
                        }
                    }
                    if defaults.bool(forKey: "demoEvidence") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            SearchModel.shared.loadDemoEvidence()
                        }
                    }
                    // 无头渲染面板到 PNG（锁屏/CI 下也能核对视觉）
                    if let dir = defaults.string(forKey: "renderPanels") {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            var panels: [(String, AnyView)] = [
                                ("onboarding-1", AnyView(OnboardingView(initialPage: 0))),
                                ("onboarding-2", AnyView(OnboardingView(initialPage: 1))),
                                ("onboarding-3", AnyView(OnboardingView(initialPage: 2))),
                                ("onboarding-4", AnyView(OnboardingView(initialPage: 3))),
                                ("settings-general", AnyView(PetSettingsView(initialPane: .general))),
                                ("settings-sensing", AnyView(PetSettingsView(initialPane: .sensing))),
                                ("settings-model", AnyView(PetSettingsView(initialPane: .model))),
                                ("rest-countdown", AnyView(RestCountdownCard(previewSeconds: 47))),
                                ("rest", AnyView(RestOverlayView(previewSeconds: 272)
                                    .frame(width: 1200, height: 760))),
                                ("menu", AnyView(MenuBarDropdown())),
                                ("notes", AnyView(NotesPanelView())),
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
                            // 截图用：news 读过后为 nil，退回最新一回，好让官网侧图用真实数据
                            if let chapter = BiographyStore.shared.news ?? BiographyStore.shared.latest {
                                panels.append(("booknews", AnyView(BookNewsCard(chapter: chapter))))
                            }
                            let renderOnly = defaults.string(forKey: "renderOnly")
                            for (name, view) in panels where renderOnly == nil || renderOnly == name {
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
                                // 等布局与 2x 重光栅化；搜索面板动画（红线 0.6+0.9s）可调大
                                let delayMs = max(defaults.integer(forKey: "renderDelayMs"), 400)
                                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
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
                            if renderOnly != nil { NSApp.terminate(nil) }
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
                    // OCR 准确性核对：启动后 5 秒把前台窗口的原始 OCR + 聊天还原
                    // dump 到指定文件——对着微信窗口跑，肉眼核对说话人和原话。
                    if let probePath = defaults.string(forKey: "ocrProbe") {
                        Task {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            await RawCapture.probe(to: probePath)
                        }
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
                // 给卡片阴影留出真实透明缓冲，避免在桌宠窗右边界被裁成黑色直条。
                .padding(.trailing, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let chapter = bio.news {
                // 《传》更新那天，它把新的一回递给你（提醒卡优先）
                BookNewsCard(chapter: chapter)
                    .padding(.trailing, 20)
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
                    .onTapGesture { PetPanels.shared.toggleNotes() }
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

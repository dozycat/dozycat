import SwiftUI

/// 桌宠本体：提醒卡 + 悬停能量胶囊 + 会换表情的猫（桌面套件）。
/// 原则：猫本身就是能量表——数字只在悬停时出现。
struct PetView: View {
    @ObservedObject private var feed = SenseFeed.shared
    @Environment(\.openSettings) private var openSettings
    @State private var hovering = false

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
                    if defaults.bool(forKey: "showChat") { PetPanels.shared.toggleChat() }
                    if defaults.bool(forKey: "demoHover") {
                        withAnimation { hovering = true }
                    }
                    if defaults.bool(forKey: "showMoods") { PetPanels.shared.showMoodBoard() }
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
            }

            ZStack(alignment: .bottom) {
                if hovering && feed.reminder == nil {
                    EnergyCapsule()
                        .offset(y: -100)
                        .transition(.opacity)
                }
                DeskCat(mood: feed.mood, size: 110)
                    .onHover { inside in
                        withAnimation(.easeOut(duration: 0.18)) { hovering = inside }
                    }
                    .onTapGesture { PetPanels.shared.toggleChat() }
            }
            .padding(.trailing, 20)
        }
        .padding(20)
        .frame(width: 420, height: 420, alignment: .bottomTrailing)
        .animation(.easeOut(duration: 0.25), value: feed.reminder)
    }
}

#Preview {
    PetView()
}

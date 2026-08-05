import SwiftUI

enum AppTab: CaseIterable {
    case today, chat, memory, review

    var label: LocalizedStringKey {
        switch self {
        case .today: return "今日"
        case .chat: return "聊天"
        case .memory: return "小传"
        case .review: return "回顾"
        }
    }
}

struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var tab: AppTab = .today
    @State private var settingsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .today: TodayView()
                case .chat: ChatView()
                case .memory: MemoryView()
                case .review: ReviewView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if tab == .today {
                    Button {
                        settingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17))
                            .foregroundStyle(DS.muted)
                            .padding(12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                }
            }

            tabBar
        }
        .sheet(isPresented: $settingsPresented) { SettingsView() }
        .background(DS.paper.ignoresSafeArea())
        .environmentObject(model)
        .fullScreenCover(isPresented: $model.restPresented) {
            RestBreakView().environmentObject(model)
        }
        .fullScreenCover(isPresented: $model.sleepPresented) {
            SleepView().environmentObject(model)
        }
        .preferredColorScheme(.light)
        .onAppear(perform: applyLaunchOverrides)
    }

    /// DEBUG: `-initialTab chat|memory|review`, `-showSleep 1`, `-showRest 1`
    /// let CI / screenshot scripts open a specific screen directly.
    private func applyLaunchOverrides() {
        #if DEBUG
        let defaults = UserDefaults.standard
        switch defaults.string(forKey: "initialTab") {
        case "chat": tab = .chat
        case "memory": tab = .memory
        case "review": tab = .review
        default: break
        }
        // Presenting a cover during the first frame is flaky — defer slightly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if defaults.bool(forKey: "showSleep") { model.sleepPresented = true }
            if defaults.bool(forKey: "showRest") { model.restPresented = true }
            if defaults.bool(forKey: "showSettings") { settingsPresented = true }
        }
        #endif
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 5) {
                        Circle()
                            .fill(tab == item ? DS.coral : .clear)
                            .frame(width: 4, height: 4)
                        Text(item.label)
                            .font(.system(size: 12, weight: tab == item ? .medium : .regular))
                            .foregroundStyle(tab == item ? DS.ink : DS.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 28)
        .background(DS.paper)
        .overlay(alignment: .top) { DS.line.frame(height: 1) }
    }
}

#Preview {
    RootView()
}

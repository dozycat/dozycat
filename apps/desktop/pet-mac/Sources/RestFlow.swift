import SwiftUI
import AppKit

enum RestPhase: Equatable {
    case idle
    case windingDown
    case resting
    case completed
}

/// 两段式休息流程：60 秒收尾，然后把主屏交给猫 5 分钟。
/// 延期按天记配额；紧急跳过会留下本机记账，避免“跳过”变成无成本按钮。
@MainActor
final class RestSession: ObservableObject {
    static let shared = RestSession()

    static let windDownSeconds = 60
    static let restSeconds = 5 * 60
    static let dailyDeferralQuota = 2

    @Published private(set) var phase: RestPhase = .idle
    @Published private(set) var secondsRemaining = 0

    private var clockTask: Task<Void, Never>?
    private var deferredStartTask: Task<Void, Never>?

    var isActive: Bool { phase == .windingDown || phase == .resting }

    var deferralsRemaining: Int {
        resetQuotaIfNeeded()
        return max(0, Self.dailyDeferralQuota - UserDefaults.standard.integer(forKey: "restDeferralsUsed"))
    }

    var countdownLabel: String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var menuLabel: String? {
        switch phase {
        case .windingDown: return String(localized: "收尾 \(countdownLabel)")
        case .resting: return String(localized: "休息 \(countdownLabel)")
        default: return nil
        }
    }

    func begin() {
        guard !isActive else { return }
        deferredStartTask?.cancel()
        phase = .windingDown
        secondsRemaining = Self.windDownSeconds
        PetPanels.shared.presentRestCountdown()
        runClock(for: .windingDown)
    }

    func restNow() {
        guard phase == .windingDown || phase == .idle else { return }
        clockTask?.cancel()
        PetPanels.shared.closeRestCountdown()
        phase = .resting
        secondsRemaining = Self.restSeconds
        PetPanels.shared.presentRestOverlay()
        runClock(for: .resting)
    }

    func deferByTenMinutes() {
        guard phase == .windingDown, deferralsRemaining > 0 else { return }
        let used = UserDefaults.standard.integer(forKey: "restDeferralsUsed") + 1
        UserDefaults.standard.set(used, forKey: "restDeferralsUsed")
        clockTask?.cancel()
        phase = .idle
        secondsRemaining = 0
        PetPanels.shared.closeRestCountdown()
        PetStore.shared.recordEnergy(phys: Double(SenseFeed.shared.phys),
                                     mind: Double(SenseFeed.shared.mind),
                                     kind: "rest-deferred")
        deferredStartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.begin()
        }
    }

    func emergencyExit() {
        guard phase == .resting else { return }
        clockTask?.cancel()
        PetPanels.shared.closeRestOverlay()
        phase = .idle
        secondsRemaining = 0
        PetStore.shared.recordEnergy(phys: Double(SenseFeed.shared.phys),
                                     mind: Double(SenseFeed.shared.mind),
                                     kind: "rest-skipped")
        PetStore.shared.addMemory(
            text: String(localized: "生理能量只剩 \(SenseFeed.shared.phys) 时，还是跳过了这次休息。"),
            note: String(localized: "硬撑")
        )
    }

    /// 生理能量第一次跌破 30 时自动进入收尾；同一天只自动触发一次。
    func considerAutoStart(phys: Int) {
        guard phys < 30, !isActive else { return }
        let today = Garden.day()
        guard UserDefaults.standard.string(forKey: "lastAutoRestDay") != today else { return }
        UserDefaults.standard.set(today, forKey: "lastAutoRestDay")
        begin()
    }

    private func runClock(for expectedPhase: RestPhase) {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self, self.phase == expectedPhase else { return }
                if self.secondsRemaining > 1 {
                    self.secondsRemaining -= 1
                } else if expectedPhase == .windingDown {
                    self.restNow()
                    return
                } else {
                    self.finish()
                    return
                }
            }
        }
    }

    private func finish() {
        clockTask?.cancel()
        secondsRemaining = 0
        phase = .completed
        PetPanels.shared.closeRestOverlay()
        PetStore.shared.recordEnergy(phys: Double(SenseFeed.shared.phys),
                                     mind: Double(SenseFeed.shared.mind),
                                     kind: "rest-completed")
        SenseFeed.shared.celebrate()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard self?.phase == .completed else { return }
            self?.phase = .idle
        }
    }

    private func resetQuotaIfNeeded() {
        let today = Garden.day()
        guard UserDefaults.standard.string(forKey: "restDeferralDay") != today else { return }
        UserDefaults.standard.set(today, forKey: "restDeferralDay")
        UserDefaults.standard.set(0, forKey: "restDeferralsUsed")
    }
}

struct RestCountdownCard: View {
    @ObservedObject private var session = RestSession.shared
    var previewSeconds: Int?

    private var remaining: Int { previewSeconds ?? session.secondsRemaining }
    private var progress: CGFloat {
        CGFloat(max(0, min(Self.duration, remaining))) / CGFloat(Self.duration)
    }
    private static let duration = RestSession.windDownSeconds

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Circle().stroke(DS.lineSoft, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(DS.coral, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)
                Text(verbatim: "\(remaining)")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(DS.ink)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 8) {
                Text("生理能量 \(SenseFeed.shared.phys)，该休息了")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Text("\(remaining) 秒后屏幕会交给猫。把这句话写完，光标我替你留住。")
                    .font(.system(size: 12))
                    .lineSpacing(5)
                    .foregroundStyle(DS.muted)

                HStack(spacing: 10) {
                    Button("现在就休") { session.restNow() }
                        .buttonStyle(SmallInkPill())
                    Button("推迟 10 分钟") { session.deferByTenMinutes() }
                        .buttonStyle(SmallGhostPill())
                        .disabled(session.deferralsRemaining == 0)
                    Text("今天还可推 \(session.deferralsRemaining) 次")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.faint)
                }
                .padding(.top, 3)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 22)
        .frame(width: 500, alignment: .leading)
        .clipShape(DesktopCardChrome.shape())
        .background(DesktopCardChrome.surface())
    }
}

struct RestOverlayView: View {
    @ObservedObject private var session = RestSession.shared
    @State private var emergencyProgress: CGFloat = 0
    var previewSeconds: Int?

    private var remaining: Int { previewSeconds ?? session.secondsRemaining }
    private var label: String {
        String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }
    private var progress: CGFloat {
        1 - CGFloat(max(0, min(RestSession.restSeconds, remaining)))
            / CGFloat(RestSession.restSeconds)
    }

    var body: some View {
        ZStack {
            DS.night.ignoresSafeArea()
            RadialGradient(colors: [DS.blue.opacity(0.12), .clear],
                           center: .center, startRadius: 40, endRadius: 330)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                HStack(spacing: 18) {
                    Text(verbatim: Date.now.formatted(date: .omitted, time: .shortened))
                    Text(verbatim: "·")
                    Text("生理能量 \(SenseFeed.shared.phys) → 休息结束约 40")
                        .foregroundStyle(DS.blue)
                }
                .font(.system(size: 12))
                .foregroundStyle(DS.nightMuted)

                Spacer()

                DeskCat(mood: .breathing, size: 180)
                Text(verbatim: label)
                    .font(.system(size: 80, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DS.nightInk)
                VStack(spacing: 7) {
                    Text("眼睛看向 6 米以外 · 肩膀转两圈 · 喝口水")
                    Text("文档、光标、剪贴板都原样留着，回来就能接上")
                }
                .font(.system(size: 13))
                .foregroundStyle(DS.nightMuted)

                Spacer()

                VStack(spacing: 14) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(DS.blue)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(width: 370, height: 2)

                    Text("长按 esc 3 秒紧急返回 · 跳过会记进《传》，本猫如实记载")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.nightMuted)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(Capsule().fill(Color.white.opacity(emergencyProgress * 0.08)))
                        .overlay(alignment: .leading) {
                            Capsule().fill(DS.coral.opacity(0.7))
                                .frame(width: 300 * emergencyProgress, height: 2)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .contentShape(Capsule())
                        .onLongPressGesture(minimumDuration: 3, maximumDistance: 30,
                                            pressing: { pressing in
                            withAnimation(.linear(duration: pressing ? 3 : 0.15)) {
                                emergencyProgress = pressing ? 1 : 0
                            }
                        }, perform: { session.emergencyExit() })
                }
                .padding(.bottom, 28)
            }
            .padding(.vertical, 30)
        }
        .accessibilityElement(children: .contain)
    }
}

/// 覆盖主屏但不进入系统全屏空间，避免切换 Space；长按 Esc 是可恢复出口。
final class RestOverlayWindow: NSPanel {
    private var eventMonitor: Any?
    private var escapeTask: Task<Void, Never>?

    init() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = NSColor(srgbRed: 0.137, green: 0.137, blue: 0.149, alpha: 1)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        canHide = false
        contentView = NSHostingView(rootView: RestOverlayView())
        setFrame(frame, display: false)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) {
            [weak self] event in
            guard event.keyCode == 53 else { return event }
            if event.type == .keyDown, !event.isARepeat {
                self?.beginEmergencyHold()
            } else if event.type == .keyUp {
                self?.escapeTask?.cancel()
                self?.escapeTask = nil
            }
            return nil
        }
    }

    override var canBecomeKey: Bool { true }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    private func beginEmergencyHold() {
        escapeTask?.cancel()
        escapeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            RestSession.shared.emergencyExit()
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        escapeTask?.cancel()
    }
}

#Preview("收尾") {
    RestCountdownCard(previewSeconds: 47)
        .padding(40)
        .background(DS.bg)
}

#Preview("休息") {
    RestOverlayView(previewSeconds: 272)
        .frame(width: 1200, height: 760)
}

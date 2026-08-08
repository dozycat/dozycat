import Foundation
import AppKit

/// FileHandle 的 readabilityHandler 是 @Sendable；把增量 JSONL 缓冲封进锁里，
/// 避免 Swift 6 下捕获并修改局部 Data 的并发错误。
private final class JSONLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ incoming: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        data.append(incoming)
        var lines: [Data] = []
        while let newline = data.firstIndex(of: 0x0A) {
            lines.append(Data(data.prefix(upTo: newline)))
            data.removeSubrange(...newline)
        }
        return lines
    }
}

/// 把 dozycat-sense（子进程）的 JSONL 语义流喂给 UI，并推导猫猫状态。
///
/// pb-os 式组合：守护进程持有原始计数与账本（EXCLUSIVE 锁的单写者），
/// UI 只消费小语义流——能量数字、nudge 与表情。
@MainActor
final class SenseFeed: ObservableObject {
    static let shared = SenseFeed()

    @Published var phys = 45
    @Published var mind = 72
    @Published var activeStreakMin = 0
    @Published var mood: CatMood = .doze
    /// 最近一分钟的劳动强度（0-1，键鼠折算）。「一段一段」写进笔记 frontmatter，
    /// 当「这几分钟用户在积极输入还是只在看」的参与度标注。不发布——UI 不显示。
    var intensity: Double = 0
    /// 连续在座分钟数（键鼠活跃 ∨ 摄像头见人）。久坐提醒的文案用它——
    /// 模型的 nudge 也是按在座算的，不能拿 activeStreakMin 顶包。
    var seatedStreakMin = 0

    /// 当前提醒卡文案（nil = 无卡）。20 秒后自己走（设计稿）。
    @Published var reminder: String?
    @Published var reminderCount = 3

    /// 搜索面板打开时猫是「好奇」——由 PetPanels 维护。
    var panelsOpen = false { didSet { refreshMood() } }

    private var process: Process?
    private var reminderDismissTask: Task<Void, Never>?
    private var happyUntil: Date?

    func start() {
        if UserDefaults.standard.bool(forKey: "demoBubble") {
            show(reminder: String(localized: "坐了 1 小时 50 分，生理能量掉到 45 了。写完这段就去接杯水？"))
        }
        // 账本归 pet（单写者）；重启从账本接续能量
        if let saved = PetStore.shared.latestEnergy() {
            phys = saved.phys
            mind = saved.mind
        }
        refreshMood()
        RestSession.shared.considerAutoStart(phys: phys)
        guard let bin = Self.senseBinary() else {
            NSLog("SenseFeed: dozycat-sense binary not found; UI runs static")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        // sense 是纯传感器：不碰账本，初始能量由 pet 注入
        var env = ProcessInfo.processInfo.environment
        env["DOZYCAT_STORE"] = "off"
        env["DOZYCAT_INIT_PHYS"] = "\(phys)"
        env["DOZYCAT_INIT_MIND"] = "\(mind)"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let buffer = JSONLineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            for line in buffer.append(handle.availableData) {
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    Task { @MainActor in self?.consume(obj) }
                }
            }
        }
        do {
            try process.run()
            self.process = process
            NSLog("SenseFeed: sensing via \(bin)")
        } catch {
            NSLog("SenseFeed: failed to launch sense: \(error)")
        }
    }

    private func consume(_ obj: [String: Any]) {
        switch obj["kind"] as? String {
        case "minute":
            let previousPhys = phys
            if let p = obj["phys"] as? Double { phys = Int(p.rounded()) }
            if let m = obj["mind"] as? Double { mind = Int(m.rounded()) }
            if let streak = obj["activeStreakMin"] as? Int { activeStreakMin = streak }
            if let seated = obj["seatedStreakMin"] as? Int { seatedStreakMin = seated }
            if let i = obj["intensity"] as? Double { intensity = i }
            PetStore.shared.recordEnergy(phys: Double(phys), mind: Double(mind), kind: "minute")
            refreshMood()
            if previousPhys >= 30, phys < 30 {
                RestSession.shared.considerAutoStart(phys: phys)
            }
        case "nudge":
            let localized = localizedBubble(kind: obj["nudge"] as? String)
            if let text = localized ?? (obj["message"] as? String) {
                reminderCount += 1
                show(reminder: text)
            }
        default:
            break
        }
    }

    // MARK: 提醒卡

    private func show(reminder text: String) {
        reminder = text
        reminderDismissTask?.cancel()
        reminderDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000) // 20 秒后自己走
            if !Task.isCancelled { self?.reminder = nil }
        }
    }

    /// 「这就去」：收卡，猫开心一会儿。
    func acknowledgeReminder() {
        reminderDismissTask?.cancel()
        reminder = nil
        happyUntil = Date().addingTimeInterval(120)
        refreshMood()
    }

    /// 做完一个回血动作：猫开心一会儿（回血清单「现在做」）。
    func celebrate() {
        happyUntil = Date().addingTimeInterval(120)
        refreshMood()
    }

    /// 「3 分钟后」：收卡，3 分钟后再来。
    func snoozeReminder() {
        reminderDismissTask?.cancel()
        let text = reminder
        reminder = nil
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000_000)
            if let text { self?.show(reminder: text) }
        }
    }

    func showFollowUp(_ text: String) {
        reminderCount += 1
        show(reminder: text)
    }

    // MARK: 猫猫状态（猫本身就是能量表）

    private func refreshMood() {
        let hour = Calendar.current.component(.hour, from: Date())
        let newMood: CatMood
        if hour >= 23 || hour < 7 {
            newMood = .asleep
        } else if panelsOpen {
            newMood = .curious
        } else if let until = happyUntil, until > Date() {
            newMood = .happy
        } else if phys < 30 {
            newMood = .drained
        } else if mind < 40 {
            newMood = .worried
        } else {
            newMood = .doze
        }
        if newMood != mood { mood = newMood }
    }

    private func localizedBubble(kind: String?) -> String? {
        switch kind {
        case "LongSitting":
            return String(localized: "坐了 \(max(seatedStreakMin, activeStreakMin)) 分钟啦，去接杯水回血？")
        case "PostMeeting":
            return String(localized: "会开完了吧？高强度输出后要补血，起来走两步～")
        case "LowPhysical":
            return String(localized: "生理能量掉到 \(phys) 了，眼睛离开屏幕一会儿好不好？")
        case "HighChurn":
            return String(localized: "感觉你在好多事之间跳，挑一件收个尾？")
        default:
            return nil
        }
    }

    private static func senseBinary() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["DOZYCAT_SENSE_BIN"],
            UserDefaults.standard.string(forKey: "senseBin"),
            Bundle.main.path(forResource: "dozycat-sense", ofType: nil),
        ]
        return candidates.compactMap { $0 }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

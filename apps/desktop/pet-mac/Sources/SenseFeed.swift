import Foundation

/// 把 dozycat-sense（子进程）的 JSONL 语义流喂给 UI。
///
/// pb-os 式组合：守护进程持有原始计数与账本（EXCLUSIVE 锁的单写者），
/// UI 只消费小语义流——能量数字与 nudge 文案。
///
/// 定位 sense 二进制（依次）：`DOZYCAT_SENSE_BIN` 环境变量 →
/// `-senseBin` 启动参数 → app bundle 资源。找不到则静态展示。
@MainActor
final class SenseFeed: ObservableObject {
    static let shared = SenseFeed()

    @Published var phys = 45
    @Published var mind = 72
    @Published var bubble: String?
    @Published var activeStreakMin = 0

    private var process: Process?
    private var bubbleClearTask: Task<Void, Never>?

    func start() {
        if UserDefaults.standard.bool(forKey: "demoBubble") {
            show(bubble: String(localized: "坐了 1 小时 50 分，生理能量掉到 45 了。写完这段，去接杯水回血？"))
        }
        guard let bin = Self.senseBinary() else {
            NSLog("SenseFeed: dozycat-sense binary not found; UI runs static")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            buffer.append(handle.availableData)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: nl)
                buffer.removeSubrange(...nl)
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
            if let p = obj["phys"] as? Double { phys = Int(p.rounded()) }
            if let m = obj["mind"] as? Double { mind = Int(m.rounded()) }
            if let streak = obj["activeStreakMin"] as? Int { activeStreakMin = streak }
        case "nudge":
            // 语义流只带 kind，文案在展示层按当前语言生成；
            // 未知 kind 回退到 sense 自带的中文 message。
            let localized = localizedBubble(kind: obj["nudge"] as? String)
            if let text = localized ?? (obj["message"] as? String) { show(bubble: text) }
        default:
            break
        }
    }

    private func localizedBubble(kind: String?) -> String? {
        switch kind {
        case "LongSitting":
            return String(localized: "坐了 \(activeStreakMin) 分钟啦，去接杯水回血？")
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

    private func show(bubble text: String) {
        bubble = text
        bubbleClearTask?.cancel()
        bubbleClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            if !Task.isCancelled { self?.bubble = nil }
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

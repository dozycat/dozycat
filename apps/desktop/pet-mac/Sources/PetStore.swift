import Foundation

/// 桌面端的真记忆库：pet 进程是 `~/.dozycat/store.db` 的单写者
/// （dozycat-core / Loro，EXCLUSIVE 锁），sense 只当纯传感器。
@MainActor
final class PetStore: ObservableObject {
    static let shared = PetStore()
    static let initialEnergy: (phys: Int, mind: Int) = (60, 60)

    private let path: String?
    private let storageDisabled: Bool
    private var store: DozyStore?
    private var lastOpenAttempt = Date.distantPast
    private var loggedUnavailable = false

    private init() {
        let configuredPath = ProcessInfo.processInfo.environment["DOZYCAT_STORE"]
            ?? AppPaths.file("store.db").path
        storageDisabled = configuredPath == "off"
        path = storageDisabled ? nil : configuredPath
        guard let path else { return }
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        _ = connectedStore(force: true)
    }

    /// Loro 使用独占锁。旧实例退出后不用重启当前 app，每隔两秒最多重试一次。
    private func connectedStore(force: Bool = false) -> DozyStore? {
        if let store { return store }
        guard let path else { return nil }

        let now = Date()
        guard force || now.timeIntervalSince(lastOpenAttempt) >= 2 else { return nil }
        lastOpenAttempt = now
        do {
            let opened = try DozyStore.open(path: path)
            store = opened
            if loggedUnavailable {
                NSLog("PetStore: store connection recovered at \(path)")
            }
            loggedUnavailable = false
            return opened
        } catch {
            if !loggedUnavailable {
                NSLog("PetStore: store unavailable at \(path); will retry (\(error))")
                loggedUnavailable = true
            }
            return nil
        }
    }

    // MARK: 回忆

    struct MemoryHit: Identifiable {
        let id: String
        let text: String
        let source: String
        let note: String?
        let at: Date
    }

    func search(_ query: String) -> [MemoryHit] {
        guard let store = connectedStore() else { return [] }
        return store.search(query: query).map(Self.hit(from:))
    }

    func recent(limit: UInt32 = 50) -> [MemoryHit] {
        guard let store = connectedStore() else { return [] }
        return store.timeline(limit: limit).map(Self.hit(from:))
    }

    func addMemory(text: String, note: String?, categories: [FfiCategory] = []) {
        guard let store = connectedStore() else { return }
        try? store.add(id: UUID().uuidString,
                       atMs: Int64(Date().timeIntervalSince1970 * 1000),
                       text: text, note: note, categories: categories)
        NSLog("PetStore: memory saved — \(text)")
    }

    /// 历史迁移：按原始时间写入（DEBUG 导入口用；正常路径走 addMemory）。
    func importMemory(atMs: Int64, text: String, note: String?) {
        guard let store = connectedStore() else { return }
        try? store.add(id: UUID().uuidString, atMs: atMs, text: text, note: note, categories: [])
    }

    /// 某个自然月的小传素材（《传》取材用），按时间升序。
    func memories(monthOf date: Date) -> [(at: Date, text: String, note: String?)] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: date) else { return [] }
        return memories(in: interval)
    }

    /// 某个时间段的小传素材（周章/月章共用），按时间升序。
    func memories(in interval: DateInterval) -> [(at: Date, text: String, note: String?)] {
        guard let store = connectedStore() else { return [] }
        return store.timeline(limit: 500)
            .compactMap { m in
                let at = Date(timeIntervalSince1970: TimeInterval(m.atMs) / 1000)
                guard interval.contains(at) else { return nil }
                return (at, m.text, m.note)
            }
            .sorted { $0.at < $1.at }
    }

    private static func hit(from m: FfiMemory) -> MemoryHit {
        let date = Date(timeIntervalSince1970: TimeInterval(m.atMs) / 1000)
        let label: String
        if Calendar.current.isDateInToday(date) {
            label = String(localized: "今天")
        } else {
            let f = DateFormatter()
            f.locale = Locale.current
            f.setLocalizedDateFormatFromTemplate("Md")
            label = f.string(from: date)
        }
        return MemoryHit(id: m.id, text: m.text,
                         source: label + String(localized: " · 倾诉"),
                         note: m.note, at: date)
    }

    // MARK: 能量（sense 的语义流由 pet 落账）

    func recordEnergy(phys: Double, mind: Double, kind: String) {
        guard !storageDisabled else { return }
        let now = Date()
        try? connectedStore()?.recordEnergy(event: FfiEnergy(
            atMs: Int64(now.timeIntervalSince1970 * 1000),
            device: "mac", phys: phys, mind: mind, kind: kind))
        // core 只留最新值；日历/K 线要历史，旁账见 EnergyLog
        EnergyLog.append(phys: phys, mind: mind, at: now)
    }

    /// 以时间戳选择账本与历史旁账里更新的一份。账本被锁时仍能从旁账稳定恢复；
    /// 锁释放后，下一次 minute 事件会自动重连并把当前状态写回正式账本。
    func latestEnergy() -> (phys: Int, mind: Int) {
        guard !storageDisabled else { return Self.initialEnergy }

        var candidates: [(at: Date, phys: Double, mind: Double)] = []
        if let e = connectedStore()?.latestEnergy() {
            candidates.append((
                Date(timeIntervalSince1970: TimeInterval(e.atMs) / 1000),
                e.phys,
                e.mind
            ))
        }
        if let sample = EnergyLog.latestSample() {
            candidates.append((sample.at, sample.phys, sample.mind))
        }
        guard let latest = candidates.max(by: { $0.at < $1.at }) else {
            return Self.initialEnergy
        }
        return (Int(latest.phys.rounded()), Int(latest.mind.rounded()))
    }
}

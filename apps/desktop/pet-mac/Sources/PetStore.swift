import Foundation

/// 桌面端的真记忆库：pet 进程是 `~/.dozycat/store.db` 的单写者
/// （dozycat-core / Loro，EXCLUSIVE 锁），sense 只当纯传感器。
@MainActor
final class PetStore: ObservableObject {
    static let shared = PetStore()

    let store: DozyStore?

    private init() {
        let path = ProcessInfo.processInfo.environment["DOZYCAT_STORE"]
            ?? (NSHomeDirectory() + "/.dozycat/store.db")
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        store = try? DozyStore.open(path: path)
        if store == nil {
            NSLog("PetStore: store unavailable at \(path) (locked by another process?)")
        }
    }

    // MARK: 回忆

    struct MemoryHit: Identifiable {
        let id: String
        let text: String
        let source: String
        let note: String?
    }

    func search(_ query: String) -> [MemoryHit] {
        guard let store else { return [] }
        return store.search(query: query).map(Self.hit(from:))
    }

    func recent(limit: UInt32 = 50) -> [MemoryHit] {
        guard let store else { return [] }
        return store.timeline(limit: limit).map(Self.hit(from:))
    }

    func addMemory(text: String, note: String?, categories: [FfiCategory] = []) {
        guard let store else { return }
        try? store.add(id: UUID().uuidString,
                       atMs: Int64(Date().timeIntervalSince1970 * 1000),
                       text: text, note: note, categories: categories)
        NSLog("PetStore: memory saved — \(text)")
    }

    /// 历史迁移：按原始时间写入（DEBUG 导入口用；正常路径走 addMemory）。
    func importMemory(atMs: Int64, text: String, note: String?) {
        guard let store else { return }
        try? store.add(id: UUID().uuidString, atMs: atMs, text: text, note: note, categories: [])
    }

    /// 某个自然月的小传素材（《传》取材用），按时间升序。
    func memories(monthOf date: Date) -> [(at: Date, text: String, note: String?)] {
        guard let store else { return [] }
        let calendar = Calendar.current
        return store.timeline(limit: 500)
            .compactMap { m in
                let at = Date(timeIntervalSince1970: TimeInterval(m.atMs) / 1000)
                guard calendar.isDate(at, equalTo: date, toGranularity: .month) else { return nil }
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
                         note: m.note)
    }

    // MARK: 能量（sense 的语义流由 pet 落账）

    func recordEnergy(phys: Double, mind: Double, kind: String) {
        try? store?.recordEnergy(event: FfiEnergy(
            atMs: Int64(Date().timeIntervalSince1970 * 1000),
            device: "mac", phys: phys, mind: mind, kind: kind))
        // core 只留最新值；日历/K 线要历史，旁账见 EnergyLog
        EnergyLog.append(phys: phys, mind: mind)
    }

    func latestEnergy() -> (phys: Int, mind: Int)? {
        guard let e = store?.latestEnergy() else { return nil }
        return (Int(e.phys.rounded()), Int(e.mind.rounded()))
    }
}

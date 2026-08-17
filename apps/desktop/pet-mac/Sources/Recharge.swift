import SwiftUI

// MARK: - 回血清单 · 你定义什么能给你充电，它学着推荐
//
// 能量 widgets 面板（日历 / K 线 / 清单 UI）已经去掉；留下的是账本本身——
// 菜单栏的「下一个提醒」和推荐逻辑还靠它。

enum RechargeKind: String, Codable {
    case phys, mind

    var color: Color { self == .phys ? DS.coral : DS.blue }
    var label: String {
        self == .phys ? String(localized: "生理") : String(localized: "心理")
    }
}

struct RechargeItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: RechargeKind
    var times = 0
    /// 事后 20 分钟量到的真实回血累计（只累计正的）。
    var measuredGain = 0.0
    var measures = 0
    var hour = 18
    var minute = 30

    var averageGain: Int? {
        measures > 0 ? Int((measuredGain / Double(measures)).rounded()) : nil
    }
}

/// 回血清单的账本：~/.dozycat/recharge.json，pet 单写者。
@MainActor
final class RechargeStore: ObservableObject {
    static let shared = RechargeStore()

    struct Recommendation {
        let key: String
        let name: String
        let reason: String
        let kind: RechargeKind
        let hour: Int
        let minute: Int
    }

    @Published private(set) var items: [RechargeItem] = []
    @Published private(set) var recommendation: Recommendation?
    private var dismissed: Set<String> = []

    private var file: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOZYCAT_RECHARGE"]
            ?? (NSHomeDirectory() + "/.dozycat/recharge.json"))
    }

    private struct Book: Codable {
        var items: [RechargeItem]
        var dismissed: [String]
    }

    private init() {
        if let data = try? Data(contentsOf: file),
           let book = try? JSONDecoder().decode(Book.self, from: data) {
            items = book.items
            dismissed = Set(book.dismissed)
        } else {
            // 第一次给三个常见的起手式，账都从 0 记
            items = [
                RechargeItem(name: String(localized: "傍晚散步 20 分钟"), kind: .phys,
                             hour: 18, minute: 30),
                RechargeItem(name: String(localized: "给妈妈打电话"), kind: .mind,
                             hour: 20, minute: 30),
                RechargeItem(name: String(localized: "弹 15 分钟琴"), kind: .mind,
                             hour: 21, minute: 0),
            ]
            save()
        }
        refreshRecommendation()
    }

    func add(name: String, kind: RechargeKind, hour: Int = 18, minute: Int = 30) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(RechargeItem(name: trimmed, kind: kind, hour: hour, minute: minute))
        save()
    }

    func remove(_ item: RechargeItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func updateSchedule(_ item: RechargeItem, hour: Int, minute: Int) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].hour = min(23, max(0, hour))
        items[index].minute = min(59, max(0, minute))
        save()
    }

    /// 「现在做」：计一次数，猫开心一会儿；20 分钟后回来量真实回了多少。
    func markDone(_ item: RechargeItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].times += 1
        save()
        SenseFeed.shared.celebrate()
        PetStore.shared.recordEnergy(phys: Double(SenseFeed.shared.phys),
                                     mind: Double(SenseFeed.shared.mind),
                                     kind: "recharge:\(item.name)")
        let before = item.kind == .phys ? SenseFeed.shared.phys : SenseFeed.shared.mind
        let id = item.id
        let kind = item.kind
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20 * 60 * 1_000_000_000)
            guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
            let after = kind == .phys ? SenseFeed.shared.phys : SenseFeed.shared.mind
            self.items[index].measuredGain += Double(max(0, after - before))
            self.items[index].measures += 1
            self.save()
        }
    }

    func acceptRecommendation() {
        guard let rec = recommendation else { return }
        add(name: rec.name, kind: rec.kind, hour: rec.hour, minute: rec.minute)
        dismissed.insert(rec.key)
        recommendation = nil
        save()
    }

    func dismissRecommendation() {
        guard let rec = recommendation else { return }
        dismissed.insert(rec.key)
        recommendation = nil
        save()
    }

    /// 推荐从真实数据里长出来：最近几天下午的生理能量持续走低才开口。
    func refreshRecommendation() {
        guard recommendation == nil, !dismissed.contains("afternoon-sun"),
              !items.contains(where: { $0.name.contains(String(localized: "太阳")) }),
              let slump = EnergyLog.hourlyPhysAverage(hours: 13..<16, days: 4),
              slump.sampleDays >= 2, slump.average < 55 else { return }
        recommendation = Recommendation(
            key: "afternoon-sun",
            name: String(localized: "午饭后在楼下晒 10 分钟太阳"),
            reason: String(localized: "最近 \(slump.sampleDays) 天下午 1 点到 3 点，生理能量平均只有 \(Int(slump.average.rounded()))，是一天里最低的一段。"),
            kind: .phys, hour: 12, minute: 40
        )
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? (try? encoder.encode(Book(items: items, dismissed: Array(dismissed))))?
            .write(to: file)
    }
}

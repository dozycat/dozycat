import Foundation

struct DozycatFollowUp: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var due: Date
    var casePath: String?
    var delivered = false
}

/// 结案报告里的“下周提醒我”不是装饰按钮：写进本机账本，应用运行时到点递回桌面。
@MainActor
final class FollowUpStore: ObservableObject {
    static let shared = FollowUpStore()

    @Published private(set) var items: [DozycatFollowUp] = []
    private var timer: Timer?

    private var file: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/.dozycat/followups.json")
    }

    private init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file),
           let decoded = try? decoder.decode([DozycatFollowUp].self, from: data) {
            items = decoded
        }
    }

    var next: DozycatFollowUp? {
        items.filter { !$0.delivered }.min { $0.due < $1.due }
    }

    @discardableResult
    func schedule(title: String, afterDays days: Int = 7, caseURL: URL?) -> DozycatFollowUp {
        let due = Calendar.current.date(byAdding: .day, value: days, to: Date())
            ?? Date().addingTimeInterval(Double(days) * 86_400)
        let followUp = DozycatFollowUp(title: title, due: due, casePath: caseURL?.path)
        items.removeAll { !$0.delivered && $0.title == title }
        items.append(followUp)
        save()
        return followUp
    }

    func start() {
        guard timer == nil else { return }
        deliverDue()
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            Task { @MainActor in FollowUpStore.shared.deliverDue() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func deliverDue() {
        guard let index = items.indices.first(where: {
            !items[$0].delivered && items[$0].due <= Date()
        }) else { return }
        let item = items[index]
        items[index].delivered = true
        save()
        SenseFeed.shared.showFollowUp(
            String(localized: "你让我今天再问一次：\(item.title)。要不要把这个案子了结？")
        )
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        // 兼容旧默认的时间编码读取：写失败不影响当前内存状态。
        if let data = try? encoder.encode(items) { try? data.write(to: file, options: .atomic) }
    }
}

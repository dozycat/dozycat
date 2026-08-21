import SwiftUI

enum EnergyKind {
    case mind, body

    var color: Color { self == .mind ? DS.blue : DS.coral }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case cat, me }
    let id = UUID()
    let role: Role
    let text: String
    /// Annotation shown under a cat message, e.g. 来自记忆 · …
    var memoryRef: String? = nil
}

struct Memory: Identifiable {
    enum Category: String, CaseIterable {
        case happy, body, people

        var label: LocalizedStringKey {
            switch self {
            case .happy: return "开心的"
            case .body: return "身体"
            case .people: return "人"
            }
        }
    }

    let id: String
    let atMs: Int64
    let text: String
    var note: String? = nil
    var categories: Set<Category> = []

    /// 身体类注记用珊瑚色，其余用蓝灰（对齐设计稿）。
    var noteKind: EnergyKind { categories.contains(.body) ? .body : .mind }

    var dateLabel: String {
        let date = Date(timeIntervalSince1970: TimeInterval(atMs) / 1000)
        if Calendar.current.isDateInToday(date) { return String(localized: "今天") }
        let formatter = DateFormatter()
        formatter.dateFormat = "M.dd"
        return formatter.string(from: date)
    }
}

extension Memory {
    init(ffi: FfiMemory) {
        self.init(
            id: ffi.id,
            atMs: ffi.atMs,
            text: ffi.text,
            note: ffi.note,
            categories: Set(ffi.categories.map { $0.appCategory })
        )
    }
}

extension FfiCategory {
    var appCategory: Memory.Category {
        switch self {
        case .happy: return .happy
        case .body: return .body
        case .people: return .people
        }
    }
}

extension Memory.Category {
    var ffi: FfiCategory {
        switch self {
        case .happy: return .happy
        case .body: return .body
        case .people: return .people
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    /// 共享内核（Rust/Loro，见 docs/MEMORY-SYNC.md）。打不开时回退内存态。
    private let store: DozyStore?

    // MARK: 能量

    @Published var mentalEnergy = 60
    @Published var physicalEnergy = 60

    // MARK: 今日

    @Published var todayMessage = String(localized: "你已经专注了两个小时，\n眼睛离开屏幕一会儿好不好？")
    @Published var showsRestActions = true
    @Published var waterCups = 4
    let waterGoal = 8
    @Published var waterTimeLabel = String(localized: "1 小时前")
    @Published var restCountToday = 4
    let restPromiseCount = 21

    // MARK: 全屏状态

    @Published var restPresented = false
    @Published var sleepPresented = false

    // MARK: 聊天

    @Published var messages: [ChatMessage] = [
        ChatMessage(
            role: .cat,
            text: String(localized: "今天和小林见面了吧？上周三你还有点紧张来着，见完感觉怎么样？"),
            memoryRef: String(localized: "来自小传 · 7月29日「有点怕见小林」")
        ),
        ChatMessage(role: .me, text: String(localized: "其实还挺好的，聊开了。就是回来路上有点空落落的")),
        ChatMessage(
            role: .cat,
            text: String(localized: "聊开了就很棒了呀。空落落也没关系，那说明这件事对你重要。要不要出去走一小圈？你每次散完步心情都会好一点，今天 21 度，刚刚好。")
        ),
    ]
    @Published var quickReplies: [String]? = [
        String(localized: "好，走一圈"),
        String(localized: "想再说说"),
    ]

    private let lazyReplies = [
        String(localized: "嗯嗯，我听着呢。不用急，慢慢说。"),
        String(localized: "好。那你现在感觉怎么样？"),
        String(localized: "记下来啦。想让我以后在合适的时候提醒你吗？"),
        String(localized: "没关系的，今天已经做得够多了。"),
    ]
    private var replyIndex = 0

    // MARK: 记忆

    @Published var memorySearch = ""
    @Published var memoryFilter: Memory.Category? = nil
    @Published var memories: [Memory] = []

    var memoryTotalLabel: String { "\(memories.count)" }

    // MARK: - 生命周期

    init() {
        store = Self.openStore()
        seedIfNeeded()
        reloadMemories()
        if let e = store?.latestEnergy() {
            mentalEnergy = Int(e.mind.rounded())
            physicalEnergy = Int(e.phys.rounded())
        }
    }

    private static func openStore() -> DozyStore? {
        do {
            let dir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("dozycat", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return try DozyStore.open(path: dir.appendingPathComponent("store.db").path)
        } catch {
            assertionFailure("dozycat-core store unavailable: \(error)")
            return nil
        }
    }

    /// 首次启动写入设计稿的样例记忆（后续启动 timeline 非空即跳过）。
    private func seedIfNeeded() {
        guard let store, store.timeline(limit: 1).isEmpty else { return }
        func daysAgo(_ d: Int) -> Int64 {
            Int64(Date().addingTimeInterval(TimeInterval(-d * 86400)).timeIntervalSince1970 * 1000)
        }
        let seeds: [(Int, String, String?, [FfiCategory])] = [
            (7, String(localized: "「有点怕见小林」——后来你们和好了"), nil, [.people]),
            (4, String(localized: "妈妈想吃你做的番茄牛腩，你说周末回家做"),
             String(localized: "暖暖的 · 周六提醒你买牛腩"), [.happy, .people]),
            (2, String(localized: "连续加班第三天，说「感觉自己像台机器」。那晚只睡了 5 小时"),
             String(localized: "很累 · 那几天我盯紧一点"), [.body]),
            (0, String(localized: "和小林见面聊开了，回来路上有点空落落的，散了一圈步"),
             String(localized: "松了口气"), [.happy, .people]),
        ]
        for (days, text, note, cats) in seeds {
            try? store.add(id: UUID().uuidString, atMs: daysAgo(days), text: text, note: note, categories: cats)
        }
    }

    private func reloadMemories() {
        guard let store else { return }
        memories = store.timeline(limit: 500).map(Memory.init(ffi:))
    }

    /// 新记忆入库（懒猫替你记的小事）。
    func addMemory(_ text: String, note: String? = nil, categories: Set<Memory.Category> = []) {
        guard let store else { return }
        try? store.add(
            id: UUID().uuidString,
            atMs: Int64(Date().timeIntervalSince1970 * 1000),
            text: text, note: note,
            categories: categories.map(\.ffi)
        )
        reloadMemories()
    }

    /// 能量变化落进跨端账本（kind 形如 "ios:water"）。
    private func recordEnergy(kind: String) {
        try? store?.recordEnergy(event: FfiEnergy(
            atMs: Int64(Date().timeIntervalSince1970 * 1000),
            device: "iphone",
            phys: Double(physicalEnergy),
            mind: Double(mentalEnergy),
            kind: kind
        ))
    }

    var filteredMemories: [Memory] {
        memories.filter { memory in
            if let filter = memoryFilter, !memory.categories.contains(filter) { return false }
            let query = memorySearch.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty {
                return memory.text.localizedCaseInsensitiveContains(query)
                    || (memory.note?.localizedCaseInsensitiveContains(query) ?? false)
            }
            return true
        }
    }

    // MARK: - Actions

    var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "早上好呀"
        case 12..<18: return "下午好呀"
        case 18..<23: return "晚上好呀"
        default: return "还没睡呀"
        }
    }

    func snooze() {
        showsRestActions = false
        todayMessage = String(localized: "好，那我 10 分钟后再来叫你。\n说好了哦。")
    }

    func finishRest(early: Bool) {
        restPresented = false
        restCountToday += 1
        physicalEnergy = min(100, physicalEnergy + 10)
        showsRestActions = false
        todayMessage = early
            ? String(localized: "回来啦。有需要我随时在。")
            : String(localized: "休息完啦，生理能量回了一点。\n下一段我 50 分钟后再提醒你。")
        recordEnergy(kind: "ios:rest")
    }

    func drinkWater() {
        guard waterCups < waterGoal else { return }
        waterCups += 1
        waterTimeLabel = String(localized: "刚刚")
        physicalEnergy = min(100, physicalEnergy + 2)
        if waterCups == waterGoal {
            todayMessage = String(localized: "喝够 8 杯水啦，今天的第一次！\n晚上我会记进「小事」里。")
            showsRestActions = false
            addMemory(String(localized: "喝够了 \(waterGoal) 杯水，第一次"), categories: [.body])
        }
        recordEnergy(kind: "ios:water")
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        quickReplies = nil
        messages.append(ChatMessage(role: .me, text: trimmed))

        // BYOK 配好就走 pi agent（带小传上下文 + save_moment 工具），否则内置回复
        if let config = SettingsStore.shared.llmConfig {
            let history = messages.suffix(12).map {
                (role: $0.role == .cat ? "assistant" : "user", content: $0.text)
            }
            let memoryContext = memories.prefix(8)
                .map { "\($0.dateLabel)：\($0.text)" }
                .joined(separator: "\n")
            var system = LLMClient.persona
            if !memoryContext.isEmpty {
                system += "\n\n你记得的关于用户的小传（可自然引用，不要逐条复述）：\n" + memoryContext
            }
            system += "\n\n如果这轮聊到了值得记进小传的一件小事（事实、情绪或约定），调用 save_moment 存下来（白描 ≤40 字 + 两三个字的情绪 note），不用告诉用户你存了。闲聊不存。"
            let saveTool = AgentTool(
                name: "save_moment",
                description: "把这轮对话里值得记住的一件小事存进用户的小传",
                parameters: ["text": ["type": "string"], "note": ["type": "string"]]
            ) { [weak self] args in
                guard let text = args["text"] as? String, !text.isEmpty else { return "text 缺失" }
                self?.addMemory(text, note: args["note"] as? String)
                return "已记下"
            }
            Task {
                do {
                    let reply = try await PiAgent.run(system: system, history: history,
                                                      tools: [saveTool], config: config, maxSteps: 4)
                    messages.append(ChatMessage(role: .cat, text: reply))
                } catch {
                    messages.append(ChatMessage(
                        role: .cat,
                        text: String(localized: "（模型连不上了…没关系，我自己也能陪你。）")
                    ))
                }
            }
        } else {
            let reply = lazyReplies[replyIndex % lazyReplies.count]
            replyIndex += 1
            replyLater(reply)
        }
    }

    func tapQuickReply(_ text: String) {
        quickReplies = nil
        messages.append(ChatMessage(role: .me, text: text))
        if text == String(localized: "好，走一圈") {
            mentalEnergy = min(100, mentalEnergy + 3)
            replyLater(String(localized: "好耶，路上慢一点。回来记得跟我说说晚霞长什么样～"))
        } else {
            replyLater(String(localized: "嗯，我在呢。想到哪儿说到哪儿就好。"))
        }
    }

    private func replyLater(_ text: String) {
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            messages.append(ChatMessage(role: .cat, text: text))
        }
    }
}

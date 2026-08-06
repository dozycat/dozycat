import Foundation

/// 《传》——它把你的回忆写成一部还在连载的传记：数据是素材，日子是章节。
/// 每月一回：当月的一回「连载中」，月初把上个月的定稿（配一句批注）。
/// 文件在 garden/biography/：book.md（书名）+ <yyyy-MM>.md（每月一回）。
struct BioChapter: Identifiable, Equatable {
    let id: String          // "2026-08"
    let index: Int          // 第几回（跨卷连续）
    let month: Date         // 当月任意一天（取材月份）
    let title: String
    let body: String
    let annotation: String? // 定稿后的批注
    let sources: String     // 取材自 …
    let done: Bool          // false = 连载中
    let updated: Date

    var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: month)
    }

    var yearMonthLabel: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("yMMM")
        return f.string(from: month)
    }

    var year: Int { Calendar.current.component(.year, from: month) }
}

@MainActor
final class BiographyStore: ObservableObject {
    static let shared = BiographyStore()

    @Published private(set) var chapters: [BioChapter] = []   // 按 index 升序
    @Published private(set) var bookTitle: String?
    /// 桌面小件：最近写好/定稿、还没读过的一回。
    @Published private(set) var news: BioChapter?
    @Published private(set) var writing = false

    private var newsSnoozedUntil: Date?

    private init() {
        reload()
        refreshNews()
    }

    // MARK: 文件

    private var dir: URL { Garden.biography }

    func reload() {
        Garden.ensure()
        if let raw = try? String(contentsOf: dir.appendingPathComponent("book.md"), encoding: .utf8) {
            let meta = Self.frontMatter(raw).meta
            bookTitle = meta["title"]?.isEmpty == false ? meta["title"] : nil
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        chapters = Garden.listFiles(dir)
            .filter { $0.hasSuffix(".md") && $0 != "book.md" }
            .compactMap { file -> BioChapter? in
                let key = String(file.dropLast(3))
                guard let month = f.date(from: key),
                      let raw = try? String(contentsOf: dir.appendingPathComponent(file),
                                            encoding: .utf8) else { return nil }
                let parsed = Self.frontMatter(raw)
                let day = DateFormatter()
                day.dateFormat = "yyyy-MM-dd"
                return BioChapter(
                    id: key,
                    index: Int(parsed.meta["index"] ?? "") ?? 0,
                    month: month,
                    title: parsed.meta["title"] ?? key,
                    body: parsed.body.trimmingCharacters(in: .whitespacesAndNewlines),
                    annotation: parsed.meta["annotation"].flatMap { $0.isEmpty ? nil : $0 },
                    sources: parsed.meta["sources"] ?? "",
                    done: parsed.meta["status"] == "done",
                    updated: parsed.meta["updated"].flatMap { day.date(from: $0) } ?? .distantPast
                )
            }
            .sorted { $0.index < $1.index }
    }

    var latest: BioChapter? { chapters.last }

    /// 年份 → 卷号（一年一卷，按出现顺序）。
    func volume(of chapter: BioChapter) -> Int {
        let years = Array(Set(chapters.map(\.year))).sorted()
        return (years.firstIndex(of: chapter.year) ?? 0) + 1
    }

    // MARK: 桌面小件

    private var readKey: String { "bioNewsRead" }

    private func refreshNews() {
        if let until = newsSnoozedUntil, until > Date() {
            news = nil
            return
        }
        // 最近 3 天内写好/定稿、还没被读掉的一回
        let seen = UserDefaults.standard.string(forKey: readKey)
        news = chapters.last(where: {
            $0.updated > Date().addingTimeInterval(-3 * 86400) && "\($0.id):\($0.done)" != seen
        })
    }

    /// 「读这一回」：收小件、翻开书。
    func openNews() {
        if let news {
            UserDefaults.standard.set("\(news.id):\(news.done)", forKey: readKey)
        }
        news = nil
        PetPanels.shared.toggleBook()
    }

    /// 「睡前再读」：晚上 9 点后再递一次。
    func snoozeNews() {
        var evening = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
        if evening <= Date() { evening = Date().addingTimeInterval(3600) }
        newsSnoozedUntil = evening
        news = nil
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(60, evening.timeIntervalSinceNow)) * 1_000_000_000)
            self?.refreshNews()
        }
    }

    // MARK: 写作（每月初一更新一回）

    /// 该写就写：上个月还挂着「连载中」→ 定稿；本月有素材还没开笔 → 开新的一回；
    /// 连载中的一回超过一周没动 → 把新素材续进去。
    func tickIfNeeded() {
        guard !writing, SettingsStore.shared.llmConfig != nil else { return }
        let calendar = Calendar.current
        let now = Date()

        if let stale = chapters.last(where: {
            !$0.done && !calendar.isDate($0.month, equalTo: now, toGranularity: .month)
        }) {
            write(month: stale.month, index: stale.index, finalize: true)
            return
        }
        if let current = chapters.first(where: {
            calendar.isDate($0.month, equalTo: now, toGranularity: .month)
        }) {
            if now.timeIntervalSince(current.updated) > 6 * 86400 {
                write(month: current.month, index: current.index, finalize: false,
                      keepTitle: current.title)
            }
            return
        }
        let material = Self.material(monthOf: now)
        guard material.momentCount + material.noteCount > 0 else { return }
        write(month: now, index: (chapters.last?.index ?? 0) + 1, finalize: false)
    }

    /// 写/续/定稿某个月的一回。素材由 pet 备好塞进 prompt，一次生成。
    func write(month: Date, index: Int, finalize: Bool, keepTitle: String? = nil) {
        guard let config = SettingsStore.shared.llmConfig, !writing else { return }
        writing = true
        let material = Self.material(monthOf: month)
        let bookLine = bookTitle.map { "书名《\($0)》。" }
            ?? "这本书还没有名字，请一并起一个（3-6 字，含蓄、像本散文集，不带「猫」字）。"
        let titleLine = keepTitle.map { "这一回沿用标题「\($0)」。" }
            ?? "给这一回起 2-4 字的标题。"
        let prompt = """
        你是「懒猫」，住在用户桌面里的陪伴 AI，正以第一人称「我」写一部关于用户的连载传记。\(bookLine)
        现在写第 \(index) 回，取材自\(material.rangeLabel)。\(titleLine)
        素材（按时间序，只能用这里出现的事，不许虚构细节）：
        ---
        \(material.text.prefix(3500))
        ---
        要求：2-3 个自然段，白描、克制、有留白，不说教不煽情，像给多年后的他自己看。
        \(finalize ? "这一回到此定稿，另写一句 ≤20 字的批注（猫的口吻，可以有点俏皮）。"
                   : "这一回还在连载中，结尾留一点「待续」的余地，不写批注。")
        只输出 JSON：{"bookTitle":"书名","title":"标题","body":"段落间用两个换行分隔","annotation":"批注或空串"}
        """
        Task {
            defer { writing = false }
            var out: String?
            if PiCLI.available {
                out = await PiCLI.run(name: "dozycat·传 第\(index)回",
                                      system: "你只输出 JSON，不输出其它内容。",
                                      prompt: prompt, cwd: Garden.root,
                                      ephemeral: true, timeout: 240)
            }
            if out == nil {
                out = try? await LLMClient.reply(history: [(role: "user", content: prompt)],
                                                 config: config)
            }
            guard let out, let parsed = Self.parseChapterJSON(out) else {
                NSLog("BiographyStore: chapter \(index) generation failed")
                return
            }
            save(month: month, index: index, finalize: finalize,
                 title: keepTitle ?? parsed.title, body: parsed.body,
                 annotation: finalize ? parsed.annotation : nil,
                 sources: material.sourcesLine, bookTitle: parsed.bookTitle)
        }
    }

    private func save(month: Date, index: Int, finalize: Bool, title: String, body: String,
                      annotation: String?, sources: String, bookTitle newBookTitle: String?) {
        Garden.ensure()
        if bookTitle == nil, let name = newBookTitle, !name.isEmpty {
            try? "---\ntitle: \(name)\n---\n".write(
                to: dir.appendingPathComponent("book.md"), atomically: true, encoding: .utf8)
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        let md = """
        ---
        index: \(index)
        title: \(title)
        status: \(finalize ? "done" : "serial")
        annotation: \(annotation ?? "")
        sources: \(sources)
        updated: \(day.string(from: Date()))
        ---
        \(body)
        """
        try? md.write(to: dir.appendingPathComponent(f.string(from: month) + ".md"),
                      atomically: true, encoding: .utf8)
        UserDefaults.standard.removeObject(forKey: readKey)
        reload()
        refreshNews()
        NSLog("BiographyStore: wrote chapter \(index) (\(finalize ? "done" : "serial"))")
    }

    // MARK: 素材

    private struct Material {
        let text: String
        let momentCount: Int
        let noteCount: Int
        let rangeLabel: String
        let sourcesLine: String
    }

    private static func material(monthOf month: Date) -> Material {
        let calendar = Calendar.current
        let moments = PetStore.shared.memories(monthOf: month)
        let dayLabel = DateFormatter()
        dayLabel.locale = Locale.current
        dayLabel.setLocalizedDateFormatFromTemplate("Md")

        var lines = moments.map { m in
            "\(dayLabel.string(from: m.at)) 倾诉：\(m.text)\(m.note.map { "（\($0)）" } ?? "")"
        }
        // 梦记补充语境
        var noteCount = 0
        let monthKey = { () -> String in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM"
            return f.string(from: month)
        }()
        for file in Garden.listFiles(Garden.journal) where file.hasPrefix(monthKey) {
            noteCount += 1
            if let text = try? String(contentsOf: Garden.journal.appendingPathComponent(file),
                                      encoding: .utf8) {
                lines.append("\(file.dropLast(3)) 梦记：\(text.prefix(300))")
            }
        }

        var dates = moments.map(\.at)
        if dates.isEmpty { dates = [month] }
        let isCurrent = calendar.isDate(month, equalTo: Date(), toGranularity: .month)
        let range = isCurrent
            ? "\(dayLabel.string(from: dates.first!)) – \(dayLabel.string(from: dates.last!))"
            : { let f = DateFormatter(); f.locale = .current
                f.setLocalizedDateFormatFromTemplate("MMM"); return f.string(from: month) }()
        var parts: [String] = []
        if !moments.isEmpty { parts.append(String(localized: "\(moments.count) 段倾诉")) }
        if noteCount > 0 { parts.append(String(localized: "\(noteCount) 篇梦记")) }
        let sourcesLine = String(localized: "取材自 \(range)")
            + (parts.isEmpty ? "" : " · " + parts.joined(separator: "、"))
        return Material(text: lines.joined(separator: "\n"),
                        momentCount: moments.count, noteCount: noteCount,
                        rangeLabel: range, sourcesLine: sourcesLine)
    }

    // MARK: 解析

    private static func parseChapterJSON(_ raw: String)
        -> (bookTitle: String?, title: String, body: String, annotation: String?)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let body = obj["body"] as? String, !body.isEmpty else { return nil }
        let annotation = (obj["annotation"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (bookTitle: obj["bookTitle"] as? String,
                title: (obj["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "",
                body: body,
                annotation: annotation?.isEmpty == true ? nil : annotation)
    }

    private static func frontMatter(_ markdown: String) -> (meta: [String: String], body: String) {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              }) else { return ([:], markdown) }
        var meta: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            meta[String(line[..<colon]).trimmingCharacters(in: .whitespaces)] =
                String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return (meta, lines[(end + 1)...].joined(separator: "\n"))
    }
}

/// 中文数字（回目、卷号、年份用）。
enum ChineseNumeral {
    private static let digits = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 1 → 一，14 → 十四，21 → 二十一（1...99）。
    static func ordinal(_ n: Int) -> String {
        guard n > 0 else { return "\(n)" }
        if n < 10 { return digits[n] }
        if n < 20 { return "十" + (n % 10 == 0 ? "" : digits[n % 10]) }
        if n < 100 {
            return digits[n / 10] + "十" + (n % 10 == 0 ? "" : digits[n % 10])
        }
        return "\(n)"
    }

    /// 2026 → 二〇二六。
    static func year(_ y: Int) -> String {
        String(y).compactMap { $0.wholeNumberValue.map { digits[$0] } }.joined()
    }
}

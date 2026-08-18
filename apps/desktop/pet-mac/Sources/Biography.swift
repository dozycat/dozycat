import Foundation

/// 《传》——它把你的回忆写成一部还在连载的传记：数据是素材，日子是章节。
/// 每周一回：新一周开始后，把上一自然周写成定稿（配一句批注）。
/// 文件在 garden/biography/：book.md（书名）+ week-<yyyy-MM-dd>.md（周一日期）。
/// 旧版 <yyyy-MM>.md 月章继续兼容；同一时间段已有周章后，月章留在磁盘但不重复展示。
struct BioChapter: Identifiable, Equatable {
    let id: String          // 旧月章 "2026-08"；周章 "week-2026-08-17"
    let index: Int          // 第几回（跨卷连续）
    let month: Date         // 取材周期起点（旧月章为月初，周章为周一）
    let title: String
    let body: String
    let annotation: String? // 定稿后的批注
    let sources: String     // 取材自 …
    let done: Bool          // false = 连载中
    let updated: Date

    var isWeekly: Bool { id.hasPrefix("week-") }

    var monthLabel: String {
        if isWeekly { return Self.weekRange(from: month, includeYear: false) }
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: month)
    }

    var yearMonthLabel: String {
        if isWeekly { return Self.weekRange(from: month, includeYear: true) }
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("yMMM")
        return f.string(from: month)
    }

    var year: Int { Calendar.current.component(.year, from: month) }

    private static func weekRange(from start: Date, includeYear: Bool) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let first = DateFormatter()
        first.locale = Locale.current
        first.setLocalizedDateFormatFromTemplate(includeYear ? "yMd" : "Md")
        let last = DateFormatter()
        last.locale = Locale.current
        last.setLocalizedDateFormatFromTemplate("Md")
        return "\(first.string(from: start))–\(last.string(from: end))"
    }
}

private enum BiographyCadence {
    case monthly
    case weekly
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
    private let weeklySinceKey = "biographyWeeklySince"

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
        let week = DateFormatter()
        week.locale = Locale(identifier: "en_US_POSIX")
        week.dateFormat = "yyyy-MM-dd"
        let loaded = Garden.listFiles(dir)
            .filter { $0.hasSuffix(".md") && $0 != "book.md" }
            .compactMap { file -> BioChapter? in
                let key = String(file.dropLast(3))
                let period = key.hasPrefix("week-")
                    ? week.date(from: String(key.dropFirst(5)))
                    : f.date(from: key)
                guard let month = period,
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
        // 回溯周记不会破坏旧月记：原文件仍保留；周章覆盖到的日期范围内，
        // 目录只展示更细的周章，避免同一段生活在书里出现两遍。
        let weekly = loaded.filter(\.isWeekly)
        if let first = weekly.map(\.month).min(),
           let last = weekly.map(\.month).max(),
           let coveredEnd = Self.isoCalendar.date(byAdding: .day, value: 7, to: last) {
            chapters = loaded.filter { chapter in
                chapter.isWeekly || chapter.month < first || chapter.month >= coveredEnd
            }.sorted { left, right in
                if left.index != right.index { return left.index < right.index }
                return left.month < right.month
            }
        } else {
            chapters = loaded.sorted { left, right in
                if left.index != right.index { return left.index < right.index }
                return left.month < right.month
            }
        }
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

    // MARK: 写作（每周更新一回）

    /// 该写就写：先收束旧版遗留的「连载中」章节；随后把刚结束的自然周
    /// 写成一回定稿。文件名以周一日期去重，因此一天调用多次也只会写一次。
    func tickIfNeeded() {
        guard !writing, SettingsStore.shared.llmConfig != nil else { return }
        let now = Date()

        if let serial = chapters.last(where: { !$0.done }) {
            write(periodStart: serial.month, index: serial.index, finalize: true,
                  cadence: serial.isWeekly ? .weekly : .monthly)
            return
        }

        let thisWeek = Self.weekStart(containing: now)
        guard let previousWeek = Self.isoCalendar.date(byAdding: .day, value: -7,
                                                       to: thisWeek) else { return }
        let firstWeek: Date
        if let saved = UserDefaults.standard.object(forKey: weeklySinceKey) as? Date {
            firstWeek = Self.weekStart(containing: saved)
        } else {
            // 升级到周章的第一天只回看刚结束的一周，避免把旧月章拆成重复周章。
            firstWeek = previousWeek
            UserDefaults.standard.set(firstWeek, forKey: weeklySinceKey)
        }

        // 离线数周后按时间顺序补齐；每次 tick 最多写一回，避免连续调用模型。
        var candidate = firstWeek
        while candidate <= previousWeek {
            let key = Self.fileKey(for: candidate, cadence: .weekly)
            if !chapters.contains(where: { $0.id == key }) {
                let material = Self.material(periodStart: candidate, cadence: .weekly)
                if material.momentCount + material.noteCount > 0 {
                    write(periodStart: candidate, index: (chapters.last?.index ?? 0) + 1,
                          finalize: true, cadence: .weekly)
                    return
                }
            }
            guard let next = Self.isoCalendar.date(byAdding: .day, value: 7,
                                                    to: candidate) else { return }
            candidate = next
        }
    }

    /// 写/续/定稿某个周期的一回。素材由 pet 备好塞进 prompt，一次生成。
    private func write(periodStart: Date, index: Int, finalize: Bool,
                       cadence: BiographyCadence, keepTitle: String? = nil) {
        guard !writing else { return }
        writing = true
        Task {
            defer { writing = false }
            _ = await generate(periodStart: periodStart, index: index, finalize: finalize,
                               cadence: cadence, keepTitle: keepTitle)
        }
    }

    /// 历史迁移后补写：从最早有素材的月份到上个月，凡没有章的都补一回（定稿）。
    func backfillHistory() async {
        let calendar = Calendar.current
        var month = calendar.date(byAdding: .month, value: -12, to: Date())!
        while !calendar.isDate(month, equalTo: Date(), toGranularity: .month) {
            let key = { let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f.string(from: month) }()
            let hasChapter = chapters.contains { $0.id == key }
            let material = Self.material(periodStart: month, cadence: .monthly)
            if !hasChapter, material.momentCount > 0, !writing {
                writing = true
                _ = await generate(periodStart: month, index: (chapters.last?.index ?? 0) + 1,
                                   finalize: true, cadence: .monthly)
                writing = false
            }
            month = calendar.date(byAdding: .month, value: 1, to: month)!
        }
        NSLog("BiographyStore: backfill done, \(chapters.count) chapters")
    }

    /// 从 Claude 会话导出回溯周记。源目录只读；每周一个文件，已存在的周章跳过，
    /// 因而中途退出后可用同一命令继续。
    @discardableResult
    func backfillSessionArchive(at suppliedRoot: URL) async -> Int {
        guard !writing, SettingsStore.shared.llmConfig != nil else { return 0 }
        guard let materials = Self.sessionArchiveMaterials(at: suppliedRoot), !materials.isEmpty else {
            NSLog("BiographyStore: no Claude session archive found at %@", suppliedRoot.path)
            return 0
        }

        writing = true
        defer { writing = false }
        var written = 0
        NSLog("BiographyStore: session backfill started (%d weeks)", materials.count)
        let pending = materials.enumerated().filter { _, material in
            let key = Self.fileKey(for: material.periodStart, cadence: .weekly)
            return !FileManager.default.fileExists(
                atPath: dir.appendingPathComponent(key + ".md").path
            )
        }

        // 三周一批并发调用同一模型；每周仍是独立 prompt、独立文件。
        // 小批次既能显著缩短历史迁移，也不会突然打出几十个请求。
        for batchStart in stride(from: 0, to: pending.count, by: 3) {
            let batch = Array(pending[batchStart..<min(batchStart + 3, pending.count)])
            let tasks = batch.map { offset, material in
                Task { @MainActor [weak self] in
                    guard let self else { return false }
                    // 历史周记自身从第一回连续编号；旧月章仍原样留在磁盘，只是不重复展示。
                    return await self.generate(periodStart: material.periodStart,
                                               index: offset + 1,
                                               finalize: true,
                                               cadence: .weekly,
                                               materialOverride: material.material,
                                               sessionArchive: true)
                }
            }
            var batchFailed = false
            for (item, task) in zip(batch, tasks) {
                if await task.value {
                    written += 1
                    NSLog("BiographyStore: session backfill progress %d/%d",
                          item.offset + 1, materials.count)
                } else {
                    batchFailed = true
                    NSLog("BiographyStore: session backfill failed at week %d", item.offset + 1)
                }
            }
            // 保持故障可见；同批已经完成的文件保留，下次会自动跳过。
            if batchFailed { break }
        }
        reload()
        refreshNews()
        NSLog("BiographyStore: session backfill done, wrote %d", written)
        return written
    }

    private func generate(periodStart: Date, index: Int, finalize: Bool,
                          cadence: BiographyCadence, keepTitle: String? = nil,
                          materialOverride: Material? = nil,
                          sessionArchive: Bool = false) async -> Bool {
        guard let config = SettingsStore.shared.llmConfig else { return false }
        let material = materialOverride ?? Self.material(periodStart: periodStart, cadence: cadence)
        let bookLine = bookTitle.map { "书名《\($0)》。" }
            ?? "这本书还没有名字，请一并起一个（3-6 字，含蓄、像本散文集，不带「猫」字）。"
        let titleLine = keepTitle.map { "这一回沿用标题「\($0)」。" }
            ?? "给这一回起 2-4 字的标题。"
        let archiveGuidance = sessionArchive ? """
        这些素材来自用户当周与 Claude 的会话，只包含会话标题和用户自己的发言。它们不是日记：
        - 优先写能确认的真实经历、决定、关系、身体状态、正在做的项目，以及反复关注或学习的方向；
        - 提问只能说明他当时在关心或思考，不能写成已经行动、已经发生或已经得出结论；
        - 忽略纯翻译、纯定义、一次性查资料等不能形成生活线索的内容；
        - 从一周的许多碎片里选 2-4 条最有分量的线索，不要罗列会话标题。
        """ : ""
        let prompt = """
        你是「懒猫」，住在用户桌面里的陪伴 AI，正以第一人称「我」写一部关于用户的连载传记。\(bookLine)
        现在写第 \(index) 回，取材自\(material.rangeLabel)。\(titleLine)
        \(archiveGuidance)
        素材（按时间序，只能用这里出现的事，不许虚构细节）：
        ---
        \(material.text.prefix(3500))
        ---
        要求：2-3 个自然段，白描、克制、有留白，不说教不煽情，像给多年后的他自己看。
        \(finalize ? "这一回到此定稿，另写一句 ≤20 字的批注（猫的口吻，可以有点俏皮）。"
                   : "这一回还在连载中，结尾留一点「待续」的余地，不写批注。")
        只输出 JSON：{"bookTitle":"书名","title":"标题","body":"段落间用两个换行分隔","annotation":"批注或空串"}
        """
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
            return false
        }
        save(periodStart: periodStart, index: index, finalize: finalize, cadence: cadence,
             title: keepTitle ?? parsed.title, body: parsed.body,
             annotation: finalize ? parsed.annotation : nil,
             sources: material.sourcesLine, bookTitle: parsed.bookTitle)
        return true
    }

    private func save(periodStart: Date, index: Int, finalize: Bool,
                      cadence: BiographyCadence, title: String, body: String,
                      annotation: String?, sources: String, bookTitle newBookTitle: String?) {
        Garden.ensure()
        if bookTitle == nil, let name = newBookTitle, !name.isEmpty {
            try? "---\ntitle: \(name)\n---\n".write(
                to: dir.appendingPathComponent("book.md"), atomically: true, encoding: .utf8)
        }
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
        try? md.write(to: dir.appendingPathComponent(
            Self.fileKey(for: periodStart, cadence: cadence) + ".md"),
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

    private struct ArchiveWeek {
        let periodStart: Date
        let material: Material
    }

    private struct ArchiveSession {
        let date: Date
        let title: String
        let file: String
        var texts: [String]

        var searchableText: String { ([title] + texts).joined(separator: " ") }
    }

    private static func material(periodStart: Date, cadence: BiographyCadence) -> Material {
        let calendar = Calendar.current
        let interval: DateInterval
        switch cadence {
        case .weekly:
            let start = weekStart(containing: periodStart)
            let end = isoCalendar.date(byAdding: .day, value: 7, to: start)!
            interval = DateInterval(start: start, end: end)
        case .monthly:
            interval = calendar.dateInterval(of: .month, for: periodStart)!
        }
        let moments = PetStore.shared.memories(in: interval)
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
            return f.string(from: periodStart)
        }()
        let fileDay = DateFormatter()
        fileDay.locale = Locale(identifier: "en_US_POSIX")
        fileDay.dateFormat = "yyyy-MM-dd"
        let journalFiles = Garden.listFiles(Garden.journal).filter { file in
            switch cadence {
            case .monthly:
                return file.hasPrefix(monthKey)
            case .weekly:
                guard file.count >= 10,
                      let date = fileDay.date(from: String(file.prefix(10))) else { return false }
                return interval.contains(date)
            }
        }
        for file in journalFiles {
            noteCount += 1
            if let text = try? String(contentsOf: Garden.journal.appendingPathComponent(file),
                                      encoding: .utf8) {
                lines.append("\(file.dropLast(3)) 梦记：\(text.prefix(300))")
            }
        }

        var dates = moments.map(\.at)
        if dates.isEmpty { dates = [periodStart] }
        let range: String
        switch cadence {
        case .weekly:
            let lastDay = isoCalendar.date(byAdding: .day, value: 6, to: interval.start)!
            range = "\(dayLabel.string(from: interval.start)) – \(dayLabel.string(from: lastDay))"
        case .monthly:
            let isCurrent = calendar.isDate(periodStart, equalTo: Date(), toGranularity: .month)
            range = isCurrent
                ? "\(dayLabel.string(from: dates.first!)) – \(dayLabel.string(from: dates.last!))"
                : { let f = DateFormatter(); f.locale = .current
                    f.setLocalizedDateFormatFromTemplate("MMM")
                    return f.string(from: periodStart) }()
        }
        var parts: [String] = []
        if !moments.isEmpty { parts.append(String(localized: "\(moments.count) 段倾诉")) }
        if noteCount > 0 { parts.append(String(localized: "\(noteCount) 篇梦记")) }
        let sourcesLine = String(localized: "取材自 \(range)")
            + (parts.isEmpty ? "" : " · " + parts.joined(separator: "、"))
        return Material(text: lines.joined(separator: "\n"),
                        momentCount: moments.count, noteCount: noteCount,
                        rangeLabel: range, sourcesLine: sourcesLine)
    }

    /// cognitive_index 是 sessions 导出附带的只含用户发言的归一化索引。
    /// 先在每周内按“生活/决定/长期项目”密度排序，再把入选会话恢复为时间序，
    /// 既不把 Claude 回答当事实，也避免一周几十次纯查询把真正的生活线索挤掉。
    private static func sessionArchiveMaterials(at suppliedRoot: URL) -> [ArchiveWeek]? {
        guard let indexURL = sessionArchiveIndex(below: suppliedRoot),
              let data = try? Data(contentsOf: indexURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["records"] as? [[String: Any]] else { return nil }

        let isoDay = DateFormatter()
        isoDay.locale = Locale(identifier: "en_US_POSIX")
        isoDay.calendar = Calendar(identifier: .gregorian)
        isoDay.timeZone = .current
        isoDay.dateFormat = "yyyy-MM-dd"

        var sessionsByFile: [String: ArchiveSession] = [:]
        for record in records {
            guard let dateText = record["date"] as? String,
                  let date = isoDay.date(from: dateText),
                  let file = record["file"] as? String else { continue }
            let title = collapseWhitespace(record["title"] as? String ?? "未命名会话")
            let cleaned = cleanArchiveText(record["text"] as? String ?? "", date: date)
            if var existing = sessionsByFile[file] {
                if !cleaned.isEmpty, !existing.texts.contains(cleaned) {
                    existing.texts.append(cleaned)
                }
                sessionsByFile[file] = existing
            } else {
                sessionsByFile[file] = ArchiveSession(
                    date: date, title: title, file: file,
                    texts: cleaned.isEmpty ? [] : [cleaned]
                )
            }
        }

        let grouped = Dictionary(grouping: sessionsByFile.values) { session in
            weekStart(containing: session.date)
        }
        return grouped.keys.sorted().compactMap { start -> ArchiveWeek? in
            guard let allSessions = grouped[start], !allSessions.isEmpty else { return nil }
            let selected = allSessions
                .sorted { left, right in
                    let leftScore = archiveScore(left)
                    let rightScore = archiveScore(right)
                    if leftScore != rightScore { return leftScore > rightScore }
                    if left.texts.count != right.texts.count { return left.texts.count > right.texts.count }
                    return left.date > right.date
                }
                .prefix(18)
                .sorted { left, right in
                    if left.date != right.date { return left.date < right.date }
                    return left.file < right.file
                }

            var lines: [String] = []
            var used = 0
            for session in selected {
                let snippets = session.texts.prefix(3).joined(separator: "；")
                let clipped = String(snippets.prefix(260))
                var line = "\(isoDay.string(from: session.date))｜\(session.title)"
                if !clipped.isEmpty { line += "｜用户发言：\(clipped)" }
                guard used + line.count <= 3450 || lines.isEmpty else { continue }
                lines.append(line)
                used += line.count + 1
            }
            guard !lines.isEmpty else { return nil }

            let last = isoCalendar.date(byAdding: .day, value: 6, to: start) ?? start
            let range = "\(isoDay.string(from: start)) – \(isoDay.string(from: last))"
            let source = "取材自 \(range) · \(allSessions.count) 段 Claude 会话"
            return ArchiveWeek(
                periodStart: start,
                material: Material(text: lines.joined(separator: "\n"),
                                   momentCount: allSessions.count,
                                   noteCount: 0,
                                   rangeLabel: range,
                                   sourcesLine: source)
            )
        }
    }

    private static func sessionArchiveIndex(below suppliedRoot: URL) -> URL? {
        let manager = FileManager.default
        if suppliedRoot.lastPathComponent == "cognitive_index.json",
           manager.fileExists(atPath: suppliedRoot.path) { return suppliedRoot }
        let direct = suppliedRoot
            .appendingPathComponent("analysis/deep-understanding/cognitive_index.json")
        if manager.fileExists(atPath: direct.path) { return direct }
        guard let enumerator = manager.enumerator(at: suppliedRoot,
                                                  includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == "cognitive_index.json" {
            return url
        }
        return nil
    }

    private static func archiveScore(_ session: ArchiveSession) -> Int {
        let text = session.searchableText.lowercased()
        let strong = [
            "老婆", "媳妇", "妻子", "女儿", "孩子", "家人", "妈妈", "爸爸", "父亲", "母亲",
            "误会", "冲突", "担心", "焦虑", "难过", "开心", "身体", "健康", "拔牙", "智齿",
            "睡眠", "跑步", "骑车", "游泳", "旅行", "签证", "搬家", "离职", "招聘", "团队",
            "创业", "公司", "工作", "产品", "项目", "决定", "计划", "复盘",
            "wife", "daughter", "family", "health", "visa", "hiring", "team", "project", "decision"
        ]
        let noise = [
            "translation", "translate", "翻译", "什么意思", "meaning", "grammar", "语法",
            "润色", "polish", "greeting", "问候", "untitled"
        ]
        let strongHits = strong.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        let noiseHits = noise.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        let substance = min(5, session.texts.reduce(0) { $0 + $1.count } / 120)
        return strongHits * 8 + substance + min(3, session.texts.count) - noiseHits * 5
    }

    private static func cleanArchiveText(_ raw: String, date: Date) -> String {
        var text = raw.replacingOccurrences(of: #"^\s*You said:\s*"#,
                                            with: "", options: .regularExpression)
        let label = DateFormatter()
        label.locale = Locale(identifier: "en_US_POSIX")
        for format in ["MMM d, yyyy", "MMM d"] {
            label.dateFormat = format
            let suffix = label.string(from: date)
            if text.hasSuffix(suffix) {
                text.removeLast(suffix.count)
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        text = collapseWhitespace(text)

        // 导出文件通常把同一条用户发言保存两遍；只在两半完全一致时去重。
        for _ in 0..<2 {
            let chars = Array(text)
            guard chars.count > 3 else { break }
            let middle = chars.count / 2
            let lower = max(1, middle - 2)
            let upper = min(chars.count - 1, middle + 2)
            var deduplicated: String?
            for split in lower...upper {
                let left = String(chars[..<split]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(chars[split...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !left.isEmpty, left == right {
                    deduplicated = left
                    break
                }
            }
            guard let deduplicated else { break }
            text = deduplicated
        }
        return text
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    private static func weekStart(containing date: Date) -> Date {
        isoCalendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? isoCalendar.startOfDay(for: date)
    }

    private static func fileKey(for periodStart: Date, cadence: BiographyCadence) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        switch cadence {
        case .weekly:
            f.dateFormat = "yyyy-MM-dd"
            return "week-" + f.string(from: weekStart(containing: periodStart))
        case .monthly:
            f.dateFormat = "yyyy-MM"
            return f.string(from: periodStart)
        }
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

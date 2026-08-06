import AppKit
import Vision

/// 花园：agent 们的文件地盘（全部本机、纯 markdown、用户可翻看）。
/// ~/.dozycat/garden/{notes/<日期>/<HHmm>_note.md, people/<名>.md, journal/<日期>.md}
enum Garden {
    static var root: URL {
        let path = ProcessInfo.processInfo.environment["DOZYCAT_GARDEN"]
            ?? (NSHomeDirectory() + "/.dozycat/garden")
        return URL(fileURLWithPath: path)
    }

    static func day(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static var notes: URL { root.appendingPathComponent("notes") }
    static var people: URL { root.appendingPathComponent("people") }
    static var journal: URL { root.appendingPathComponent("journal") }
    static var biography: URL { root.appendingPathComponent("biography") }

    static func ensure() {
        for dir in [notes, people, journal, biography] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func listFiles(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
    }
}

// MARK: - Sequence agent：screen + 其它输入 → 时间_note.md

/// 每 5 分钟一跑：屏幕文字（本机 Vision OCR，不出设备）+ 前台应用 + 能量，
/// 让模型写一段白描，落成 notes/<日期>/<HHmm>_note.md。
@MainActor
enum SequenceAgent {
    static func run() async -> String? {
        Garden.ensure()
        let feed = SenseFeed.shared
        // 前台应用；如果此刻前台是懒猫自己（面板/搜索开着），不算数
        let front = NSWorkspace.shared.frontmostApplication
        let app = front?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? "" : (front?.localizedName ?? "")
        let appBundleID = front?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? "" : (front?.bundleIdentifier ?? "")
        let ocr = await screenText()

        var body = ""
        if let config = SettingsStore.shared.llmConfig, !ocr.isEmpty {
            let prompt = """
            以下是刚刚几分钟用户屏幕上的文字片段（本机 OCR，可能零碎）：
            ---
            \(ocr.prefix(3000))
            ---
            前台应用：\(app)。用 2-3 句第三人称白描用户在做的事：只写屏幕上可见的事实
            （在和谁说什么、看什么、约了什么），不要想象动作、表情或心理活动。
            如果屏幕清楚显示了文件或目录的绝对路径，必须保留准确路径并写成 Markdown 链接：
            [文件名](file:///绝对路径)。没有完整路径就不要猜，也不要把普通文字伪装成链接。
            屏幕上出现的具体人名（含「X医生」这类称呼）最后单独一行写「人物：名字1、名字2」，没有则写「人物：无」。
            """
            body = (try? await LLMClient.reply(history: [(role: "user", content: prompt)],
                                               config: config)) ?? ""
        }

        let time = DateFormatter(); time.dateFormat = "HHmm"
        var stamp = time.string(from: Date())
        let local = DateFormatter()
        local.dateFormat = "yyyy-MM-dd HH:mm"
        let appLabel = app.replacingOccurrences(of: "]", with: "\\]")
        let appContext = app.isEmpty ? "" : (appBundleID.isEmpty
            ? "使用：\(app)"
            : "使用：[\(appLabel)](app://\(appBundleID))")
        let md = """
        ---
        time: \(local.string(from: Date()))（本地时间）
        app: \(app)
        appBundleID: \(appBundleID)
        phys: \(feed.phys)
        mind: \(feed.mind)
        activeStreakMin: \(feed.activeStreakMin)
        ---
        \(appContext)

        \(body.isEmpty ? "（无屏幕内容）" : body)
        """
        let dayDir = Garden.notes.appendingPathComponent(Garden.day())
        try? FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        // 同一分钟多次运行不覆盖：加秒后缀
        var file = dayDir.appendingPathComponent("\(stamp)_note.md")
        if FileManager.default.fileExists(atPath: file.path) {
            let sec = DateFormatter(); sec.dateFormat = "HHmmss"
            stamp = sec.string(from: Date())
            file = dayDir.appendingPathComponent("\(stamp)_note.md")
        }
        try? md.write(to: file, atomically: true, encoding: .utf8)
        NSLog("SequenceAgent: wrote \(file.lastPathComponent)")
        return file.path
    }

    /// 屏幕文字：测试注入（DOZYCAT_FAKE_OCR）优先；真跑走 screencapture + Vision，
    /// 首次会触发系统「屏幕录制」授权。截图用后即删，文字不出设备（只有白描给模型）。
    private static func screenText() async -> String {
        if let fake = ProcessInfo.processInfo.environment["DOZYCAT_FAKE_OCR"] { return fake }
        let tmp = NSTemporaryDirectory() + "dz-seq-\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", tmp]
        try? proc.run()
        proc.waitUntilExit()
        guard let image = NSImage(contentsOfFile: tmp),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.prefix(60).joined(separator: "\n"))
            }
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.recognitionLevel = .accurate
            DispatchQueue.global().async {
                let handler = VNImageRequestHandler(cgImage: cg)
                if (try? handler.perform([request])) == nil {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}

// MARK: - Dream agent：时间笔记 → 人物、关系、值得记住的小事

/// 定期「做梦」：翻最近的时间笔记，维护人物卡（谁、和用户什么关系、最近温度），
/// 把真正值得记住的小事存进小传（一天 ≤3 条），写一篇短梦记。
@MainActor
enum DreamAgent {
    static func run() async -> String {
        Garden.ensure()
        guard let config = SettingsStore.shared.llmConfig else {
            return "no model configured"
        }
        let today = Garden.day()

        // 真 pi 优先：session 落 ~/.pi/agent/sessions，工具用 pi 自带的 read/bash/write
        if PiCLI.available {
            MomentsBridge.writeSnapshot()
            let system = """
            你是「懒猫」的梦，工作目录就是懒猫的花园（notes/<日期>/ 时间笔记、
            people/ 人物卡、journal/ 梦记、moments_snapshot.md 小传快照）。
            用你的文件和 bash 工具翻今天的笔记，只搞清楚三件事：
            1) 人物——谁反复出现；2) 关系——对用户意味着什么、最近温度（亲近/紧张/疏远）
            及带日期的证据；3) 用户本人——累不累、答应过什么、情绪与身体信号。
            然后：更新/合并 people/<名>.md（保留旧证据）；\(MomentsBridge.howToSave)
            最后写 journal/\(today).md（≤5 句）。铁律：笔记里没有的不写；不确定的人名不建卡。
            """
            if let out = await PiCLI.run(name: "dozycat·梦 \(today)", system: system,
                                         prompt: "今天是 \(today)。开始吧。",
                                         cwd: Garden.root, timeout: 600) {
                let saved = MomentsBridge.ingest()
                return out + (saved.isEmpty ? "" : "\n[已入库 \(saved.count) 条小传]")
            }
        }
        let system = """
        你是「懒猫」的梦。你翻用户的时间笔记，只搞清楚三件事：
        1) 人物——谁在用户生活里反复出现；
        2) 关系——这个人对用户意味着什么，最近的温度（亲近/紧张/疏远）有没有变化，证据是什么；
        3) 用户本人——累不累、答应过自己或别人什么、情绪走向、身体信号（睡眠/久坐/疼痛）。
        做法：先 list_notes 看今天有什么，逐条 read_note；再 list_people 看已有人物卡，
        有新信息就 read_person 后用 write_person 合并更新（保留旧证据，新证据带日期）。
        用 save_moment 存今天真正值得记住的小事——宁缺毋滥，白描 ≤40 字，
        note 是两三个字的情绪词（可加 · 跟进动作）。
        最后 write_journal 写 ≤5 句的今日梦记（人物动态 + 用户状态一句话）。
        铁律：笔记里没有的不写；不确定的人名不建卡；隐私内容只留白描不留原文。
        """
        return (try? await PiAgent.run(
            system: system,
            history: [(role: "user", content: "今天是 \(today)。开始吧。")],
            tools: tools(),
            config: config,
            maxSteps: 20,
            onStep: { NSLog("DreamAgent step: \($0)") }
        )) ?? "dream failed"
    }

    private static func tools() -> [AgentTool] {
        [
            AgentTool(name: "list_notes",
                      description: "列出某天的时间笔记文件名。day 形如 2026-08-06，省略 = 今天",
                      parameters: ["day": ["type": "string"]]) { args in
                let day = args["day"] as? String ?? Garden.day()
                let files = Garden.listFiles(Garden.notes.appendingPathComponent(day))
                return files.isEmpty ? "（这天没有笔记）" : files.joined(separator: "\n")
            },
            AgentTool(name: "read_note",
                      description: "读一条时间笔记。name = 文件名，day 省略 = 今天",
                      parameters: ["name": ["type": "string"], "day": ["type": "string"]]) { args in
                let day = args["day"] as? String ?? Garden.day()
                let url = Garden.notes.appendingPathComponent(day)
                    .appendingPathComponent(args["name"] as? String ?? "")
                return (try? String(contentsOf: url, encoding: .utf8)) ?? "（读不到）"
            },
            AgentTool(name: "list_people",
                      description: "列出已有的人物卡",
                      parameters: [:]) { _ in
                let files = Garden.listFiles(Garden.people)
                return files.isEmpty ? "（还没有人物卡）" : files.joined(separator: "\n")
            },
            AgentTool(name: "read_person",
                      description: "读一张人物卡。name 可带或不带 .md",
                      parameters: ["name": ["type": "string"]]) { args in
                let name = normalized(args["name"])
                let url = Garden.people.appendingPathComponent("\(name).md")
                return (try? String(contentsOf: url, encoding: .utf8)) ?? "（还没有这张卡）"
            },
            AgentTool(name: "write_person",
                      description: "写/覆盖一张人物卡。content 用 markdown：关系一句话、最近温度、证据（带日期）",
                      parameters: ["name": ["type": "string"], "content": ["type": "string"]]) { args in
                let name = normalized(args["name"])
                guard !name.isEmpty, let content = args["content"] as? String else { return "参数缺失" }
                let url = Garden.people.appendingPathComponent("\(name).md")
                try? content.write(to: url, atomically: true, encoding: .utf8)
                return "已更新 \(name).md"
            },
            AgentTool(name: "save_moment",
                      description: "把一件值得记住的小事存进用户小传。text ≤40字白描；note 情绪词（可选 · 跟进）",
                      parameters: ["text": ["type": "string"], "note": ["type": "string"]]) { args in
                guard let text = args["text"] as? String, !text.isEmpty else { return "text 缺失" }
                let todayCount = PetStore.shared.recent(limit: 50).filter {
                    $0.source.hasPrefix(String(localized: "今天"))
                }.count
                if todayCount >= 3 {
                    return "今天已有 \(todayCount) 条小传，只在明显更重要时才值得再存。这条先放弃。"
                }
                PetStore.shared.addMemory(text: text, note: args["note"] as? String)
                return "已记下：\(text)"
            },
            AgentTool(name: "write_journal",
                      description: "写今天的梦记（≤5 句 markdown）",
                      parameters: ["content": ["type": "string"]]) { args in
                guard let content = args["content"] as? String else { return "参数缺失" }
                let url = Garden.journal.appendingPathComponent("\(Garden.day()).md")
                try? content.write(to: url, atomically: true, encoding: .utf8)
                return "梦记已写"
            },
        ]
    }

    private static func normalized(_ raw: Any?) -> String {
        var name = (raw as? String ?? "").trimmingCharacters(in: .whitespaces)
        if name.hasSuffix(".md") { name = String(name.dropLast(3)) }
        return name.replacingOccurrences(of: "/", with: "-")
    }
}

// MARK: - Searcher agent：忘了什么事，帮你翻出线索（agentic RAG）

/// Search Everything 的问句模式：多轮翻小传、时间笔记、人物卡、本机文件，
/// 换关键词反复试，直到找到线索或诚实说没有。
@MainActor
enum SearcherAgent {
    static func run(question: String,
                    onStep: ((String) -> Void)? = nil) async throws -> (answer: String, sources: [PetStore.MemoryHit]) {
        Garden.ensure()
        guard let config = SettingsStore.shared.llmConfig else {
            return (String(localized: "（要先在设置里配一个模型，我才能翻着回忆回答你。）"), [])
        }

        // 真 pi 优先：bash grep 笔记/小传快照/人物卡 + mdfind 搜本机文件
        if PiCLI.available {
            MomentsBridge.writeSnapshot()
            let system = """
            用户忘了件事，你帮 ta 找线索。工作目录是懒猫的花园：
            notes/<日期>/ 时间笔记、people/ 人物卡、moments_snapshot.md 小传快照。
            用 bash 的 grep -r 翻这些文件（中文关键词用 1-2 字短词、换说法多试几次）；
            需要搜用户本机文件时用 mdfind -onlyin ~ "kMDItemFSName == '*词*'cd"。
            找到了：用懒猫的口吻回答，总共不超过两句，顺口说线索来自哪（几号的笔记/小传），
            不用 emoji。严格按线索原文说，别脑补。实在没有：一句话诚实说没找到 + 猜一个最可能的去处。
            """
            if let out = await PiCLI.run(name: "dozycat·找线索", system: system,
                                         prompt: question, cwd: Garden.root, timeout: 240) {
                let hits = PetStore.shared.search(question) // 顺带给 UI 一份可点的来源
                return (out, Array(hits.prefix(4)))
            }
        }

        var collectedHits: [PetStore.MemoryHit] = []

        let tools: [AgentTool] = [
            AgentTool(name: "search_moments",
                      description: "按关键词搜用户的小传（子串匹配，中文建议用 1-2 个字的关键词多试几次）",
                      parameters: ["q": ["type": "string"]]) { args in
                let q = args["q"] as? String ?? ""
                let hits = PetStore.shared.search(q)
                for hit in hits where !collectedHits.contains(where: { $0.id == hit.id }) {
                    collectedHits.append(hit)
                }
                return hits.isEmpty ? "（没搜到）"
                    : hits.prefix(6).map { "\($0.source)：\($0.text)\($0.note.map { " [\($0)]" } ?? "")" }
                        .joined(separator: "\n")
            },
            AgentTool(name: "grep_notes",
                      description: "在最近 7 天的时间笔记里全文找关键词，返回命中行和文件",
                      parameters: ["q": ["type": "string"]]) { args in
                let q = args["q"] as? String ?? ""
                guard !q.isEmpty else { return "q 缺失" }
                var out: [String] = []
                for day in recentDays(7) {
                    let dir = Garden.notes.appendingPathComponent(day)
                    for file in Garden.listFiles(dir) {
                        let url = dir.appendingPathComponent(file)
                        guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                        for line in text.split(separator: "\n") where line.localizedCaseInsensitiveContains(q) {
                            out.append("\(day)/\(file)：\(line.prefix(120))")
                            if out.count >= 12 { return out.joined(separator: "\n") }
                        }
                    }
                }
                return out.isEmpty ? "（没搜到）" : out.joined(separator: "\n")
            },
            AgentTool(name: "read_note",
                      description: "读某天的一条时间笔记原文。day 形如 2026-08-06",
                      parameters: ["day": ["type": "string"], "name": ["type": "string"]]) { args in
                let url = Garden.notes.appendingPathComponent(args["day"] as? String ?? Garden.day())
                    .appendingPathComponent(args["name"] as? String ?? "")
                return (try? String(contentsOf: url, encoding: .utf8)) ?? "（读不到）"
            },
            AgentTool(name: "list_people",
                      description: "列出人物卡", parameters: [:]) { _ in
                let files = Garden.listFiles(Garden.people)
                return files.isEmpty ? "（还没有人物卡）" : files.joined(separator: "\n")
            },
            AgentTool(name: "read_person",
                      description: "读一张人物卡",
                      parameters: ["name": ["type": "string"]]) { args in
                var name = (args["name"] as? String ?? "")
                if name.hasSuffix(".md") { name = String(name.dropLast(3)) }
                let url = Garden.people.appendingPathComponent("\(name).md")
                return (try? String(contentsOf: url, encoding: .utf8)) ?? "（没有这张卡）"
            },
            AgentTool(name: "search_files",
                      description: "按文件名搜本机文件（Spotlight），返回路径",
                      parameters: ["q": ["type": "string"]]) { args in
                let hits = await SearchModel.mdfind(args["q"] as? String ?? "")
                return hits.isEmpty ? "（没搜到文件）"
                    : hits.map { "\($0.name) — \($0.folder)" }.joined(separator: "\n")
            },
        ]

        let system = """
        用户忘了件事，你帮 ta 找线索。你有这些地方可以翻：小传（search_moments）、
        最近的时间笔记（grep_notes / read_note）、人物卡（list_people / read_person）、
        本机文件名（search_files）。
        方法：把问题拆成 2-3 个不同说法的关键词，中文用短词（1-2 字）逐个试；
        小传没有就翻笔记，涉及人就看人物卡。最多试六七次。
        找到了：用懒猫的口吻回答，总共不超过两句话，顺口说线索来自哪（几号的笔记/小传），
        不用 emoji，不给建议清单。严格按线索原文说，别脑补细节。
        实在没有：一句话诚实说没找到 + 猜一个最可能的去处。不要编造。
        """
        let answer = try await PiAgent.run(
            system: system,
            history: [(role: "user", content: question)],
            tools: tools,
            config: config,
            maxSteps: 12,
            onStep: onStep
        )
        return (answer, collectedHits)
    }

    private static func recentDays(_ n: Int) -> [String] {
        (0..<n).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: Date()).map { Garden.day($0) }
        }
    }
}

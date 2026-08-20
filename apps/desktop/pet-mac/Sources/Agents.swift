import AppKit
@preconcurrency import Vision

/// 花园：agent 们的文件地盘（全部本机、纯 markdown、用户可翻看）。
/// ~/.dozycat/garden/{notes/<日期>/<HHmm>_note.md, people/<名>.md, journal/<日期>.md,
/// links/<名>.md 链接卡（指向本机文件或外部网页）, cases/<日期>-<序号>.md 结案报告}
enum Garden {
    static var root: URL {
        let path = ProcessInfo.processInfo.environment["DOZYCAT_GARDEN"]
        return path.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? AppPaths.directory("garden")
    }

    static func day(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static var notes: URL { root.appendingPathComponent("notes") }
    static var people: URL { root.appendingPathComponent("people") }
    static var journal: URL { root.appendingPathComponent("journal") }
    static var biography: URL { root.appendingPathComponent("biography") }
    static var links: URL { root.appendingPathComponent("links") }
    static var cases: URL { root.appendingPathComponent("cases") }
    static var jots: URL { root.appendingPathComponent("jots") }

    static func ensure() {
        for dir in [notes, people, journal, biography, links, cases, jots] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func listFiles(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
    }
}

// MARK: - 一段一段（sequence）：原料段 → 时间_note.md（带 cite）

/// 「一段一段」：每 5 分钟一跑，把这段时间里原料层攒下的高频 OCR 段
/// （RawCapture，本机、免费）串起来，让模型写一条时间笔记，落成
/// notes/<日期>/<HHmm>_note.md。纪律：人和人说的原话是最重要的内容——
/// 对话摘录一字不改地留；每条事实标注出自哪份原料（cite），frontmatter 的
/// sources 列出全部原料路径，随时能找回当时的原始输入。
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

        // 原料优先：过去 6 分钟的高频段。原料层没跑起来时退回瞬时 OCR（无 cite）。
        var segments = RawCapture.segments(since: Date().addingTimeInterval(-360))
        var fallbackOCR = ""
        if segments.isEmpty {
            fallbackOCR = await screenText()
        }
        // 活动类别（带屏幕文字的精分类）喂给疲劳感知——跨边界的只有类别标签
        let classifyText = segments.map(\.text).joined(separator: "\n") + fallbackOCR
        SenseHintsPump.shared.updateActivity(
            ActivityClass.classify(app: app, bundleID: appBundleID, ocr: classifyText))
        guard !segments.isEmpty || !fallbackOCR.isEmpty else {
            let reason = RawCapture.hasScreenCaptureAccess
                ? "OCR returned no text"
                : "screen recording permission unavailable"
            NSLog("SequenceAgent: skipped — %@", reason)
            return nil
        }

        // 控制上下文：从最新往回收，总量 ~7000 字放得下几段对话
        var budget = 7000
        var kept: [RawCapture.Segment] = []
        for seg in segments.reversed() {
            budget -= seg.text.count
            if budget < 0 && !kept.isEmpty { break }
            kept.append(seg)
        }
        segments = kept.reversed()

        var body = ""
        if let config = SettingsStore.shared.llmConfig,
           !(segments.isEmpty && fallbackOCR.isEmpty) {
            let material = segments.isEmpty
                ? "【原料】（瞬时 OCR，无存档）\n\(fallbackOCR.prefix(3000))"
                : segments.enumerated().map { i, seg in
                    "【原料\(i + 1) \(seg.ref)】\n\(seg.text)"
                }.joined(separator: "\n\n")
            let prompt = """
            以下是刚刚几分钟里前台窗口的文字原料（本机 OCR，按时间排列；
            「对方：/我：」是按气泡位置还原的说话人，可能有识别噪音）：
            ---
            \(material)
            ---
            前台应用：\(app)。写一条时间笔记，两部分：
            1) 用 2-3 句第三人称白描用户在做的事：只写原料里可见的事实
               （在和谁说什么、看什么、约了什么），不要想象动作、表情或心理活动。
            2) 原料里有人和人的对话时，加一节「## 对话摘录」，挑最要紧的原话逐条保留
               （每行「说话人：「原话」」，原话一字不改，最多 8 条；闲聊寒暄可略）。
            每条白描和每条摘录末尾用（原料N）标注出处；拿不准出处就不写这条。
            原料里清楚显示的文件/目录绝对路径写成 [文件名](file:///绝对路径)，
            没有完整路径不要猜。出现的具体人名（含「X医生」这类称呼）最后单独一行
            写「人物：名字1、名字2」，没有则写「人物：无」。
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
        // sources 由代码落死，不依赖模型——「找到当时的原始输入」是硬保证
        let sourceLines = segments.isEmpty ? ""
            : "\nsources:\n" + segments.map { "  - \($0.ref)" }.joined(separator: "\n")
        let md = """
        ---
        time: \(local.string(from: Date()))（本地时间）
        app: \(app)
        appBundleID: \(appBundleID)
        phys: \(feed.phys)
        mind: \(feed.mind)
        activeStreakMin: \(feed.activeStreakMin)
        intensity: \(String(format: "%.2f", feed.intensity))\(sourceLines)
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

    /// 屏幕文字（原料层没跑起来时的兜底）：测试注入（DOZYCAT_FAKE_OCR）优先；
    /// 真跑走 ScreenCaptureKit 内存直采 + Vision，首次触发系统「屏幕录制」授权。
    /// 像素只活在内存里、OCR 完即弃——**磁盘上从不出现截图文件**；
    /// 文字不出设备（只有白描给模型）。
    private static func screenText() async -> String {
        if let fake = ProcessInfo.processInfo.environment["DOZYCAT_FAKE_OCR"] { return fake }
        guard let cg = await RawCapture.frontWindowImage() else { return "" }
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

// MARK: - 一片一片（dream）：时间笔记 → 人物、关系、值得记住的小事

/// 「一片一片」：定期做梦，翻最近的时间笔记，维护人物卡（谁、和用户什么关系、
/// 最近温度），把真正值得记住的小事存进小传（一天 ≤3 条），写一篇短梦记。
/// 纪律：用了哪段笔记要记得——证据必须带出处（笔记路径），梦记末尾列「取材」。
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
            你是「懒猫」的梦（一片一片），工作目录就是懒猫的花园（notes/<日期>/ 时间笔记、
            people/ 人物卡、journal/ 梦记、links/ 链接卡、raw/ 原料段、jots/ 用户便签、moments_snapshot.md 小传快照）。
            花园是搜索的地基：所有和用户相关的信息都要组织到这里。
            jots/<日期>.md 是用户主动记给你的便签（一行一条）——这是他特意想让你
            知道的事，优先读、优先当证据；比屏幕上偶然看到的更重要。
            用你的文件和 bash 工具翻今天的笔记和便签，只搞清楚三件事：
            1) 人物——谁反复出现；2) 关系——对用户意味着什么、最近温度（亲近/紧张/疏远）
            及带日期的证据；3) 用户本人——累不累、答应过什么、情绪与身体信号。
            然后：更新/合并 people/<名>.md（保留旧证据）。人物卡的证据优先引用笔记
            「对话摘录」里的原话，每条证据末尾标注出处（日期 + 笔记路径，如
            notes/\(today)/1032_note.md）——用了哪段笔记必须记得，出处追不到的不写。
            \(MomentsBridge.howToSave)
            笔记里出现的、和用户有关的本机文件路径或网页链接，写成 links/<名>.md 链接卡：
            frontmatter 三行（target: 绝对路径或 URL / date: \(today) / why: 一句话为什么值得留），
            正文一两句白描。已有同名卡就合并更新，别的机器路径或猜的路径不建卡。
            最后写 journal/\(today).md（≤5 句），末尾一行「取材：」列出你实际用到的笔记路径。
            铁律：笔记里没有的不写；不确定的人名不建卡。
            """
            if let out = await PiCLI.run(name: "dozycat·一片一片 \(today)", system: system,
                                         prompt: "今天是 \(today)。开始吧。",
                                         cwd: Garden.root, timeout: 600) {
                let saved = MomentsBridge.ingest()
                return out + (saved.isEmpty ? "" : "\n[已入库 \(saved.count) 条小传]")
            }
        }
        let system = """
        你是「懒猫」的梦（一片一片）。你翻用户的时间笔记和便签（jots/<日期>.md
        是用户主动记给你的，优先读、优先当证据），只搞清楚三件事：
        1) 人物——谁在用户生活里反复出现；
        2) 关系——这个人对用户意味着什么，最近的温度（亲近/紧张/疏远）有没有变化，证据是什么；
        3) 用户本人——累不累、答应过自己或别人什么、情绪走向、身体信号（睡眠/久坐/疼痛）。
        做法：先 list_notes 看今天有什么，逐条 read_note；再 list_people 看已有人物卡，
        有新信息就 read_person 后用 write_person 合并更新（保留旧证据，新证据带日期）。
        人物卡的证据优先引用笔记「对话摘录」里的原话，每条证据末尾标注出处
        （日期 + 笔记文件名）——用了哪段笔记必须记得，出处追不到的不写。
        用 save_moment 存今天真正值得记住的小事——宁缺毋滥，白描 ≤40 字，
        note 是两三个字的情绪词（可加 · 跟进动作）。
        笔记里出现的、和用户有关的本机文件路径用 link_file 收进花园，
        网页链接用 link_url——花园是搜索的地基，值得再找到的东西都要留一张链接卡。
        最后 write_journal 写 ≤5 句的今日梦记（人物动态 + 用户状态一句话），
        末尾一行「取材：」列出你实际用到的笔记文件。
        铁律：笔记里没有的不写；不确定的人名不建卡；路径是猜的不建链接卡。
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
            AgentTool(name: "read_jots",
                      description: "读用户主动记给你的便签（jots/<日期>.md，一行一条）。day 省略 = 今天",
                      parameters: ["day": ["type": "string"]]) { args in
                let day = args["day"] as? String ?? Garden.day()
                let url = Garden.jots.appendingPathComponent("\(day).md")
                return (try? String(contentsOf: url, encoding: .utf8)) ?? "（这天没有便签）"
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
            AgentTool(name: "link_file",
                      description: "把一个和用户相关的本机文件收进花园（links/ 链接卡）。path 绝对路径；why 一句话为什么值得留",
                      parameters: ["path": ["type": "string"], "why": ["type": "string"]]) { args in
                let raw = (args["path"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let expanded = (raw as NSString).expandingTildeInPath
                guard !expanded.isEmpty, FileManager.default.fileExists(atPath: expanded) else {
                    return "（这个路径在本机不存在，不建卡）"
                }
                return writeLinkCard(target: expanded,
                                     name: URL(fileURLWithPath: expanded).lastPathComponent,
                                     why: args["why"] as? String)
            },
            AgentTool(name: "link_url",
                      description: "把一个和用户相关的网页链接收进花园（links/ 链接卡）。url 完整地址；title 名字；why 一句话",
                      parameters: ["url": ["type": "string"], "title": ["type": "string"],
                                   "why": ["type": "string"]]) { args in
                let raw = (args["url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                guard let url = URL(string: raw),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                    return "（只收 http/https 链接）"
                }
                let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespaces)
                return writeLinkCard(target: raw,
                                     name: (title?.isEmpty == false ? title! : (url.host ?? "链接")),
                                     why: args["why"] as? String)
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

    /// 链接卡：links/<名>.md，frontmatter 带 target/date/why，正文可日后追写。
    static func writeLinkCard(target: String, name: String, why: String?) -> String {
        Garden.ensure()
        let slug = name.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespaces)
        guard !slug.isEmpty else { return "名字不能为空" }
        let url = Garden.links.appendingPathComponent("\(slug).md")
        let reason = (why ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let md = """
        ---
        target: \(target)
        date: \(Garden.day())
        why: \(reason)
        ---
        [\(slug)](\(target.hasPrefix("/") ? "file://" + target : target))
        """
        try? md.write(to: url, atomically: true, encoding: .utf8)
        return "已收进花园：links/\(slug).md"
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
            用户忘了件事，你帮 ta 找线索。工作目录是懒猫的花园（搜索的地基）：
            notes/<日期>/ 时间笔记、people/ 人物卡、links/ 链接卡、moments_snapshot.md 小传快照。
            用 bash 的 grep -r 翻这些文件（中文关键词用 1-2 字短词、换说法多试几次）；
            花园里没有、需要搜用户本机文件时才用 mdfind -onlyin ~ "kMDItemFSName == '*词*'cd"。
            找到了：用懒猫的口吻输出两行——第一行以「推理：」开头，一句话说线索怎么串起来的
            （顺口带上来自几号的笔记/小传）；第二行以「结论：」开头，一句话直接回答。
            不用 emoji。严格按线索原文说，别脑补。
            实在没有：只输出一行「结论：」——诚实说没找到 + 猜一个最可能的去处。
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
            AgentTool(name: "grep_links",
                      description: "在花园的链接卡（links/）里找关键词，返回卡名和指向",
                      parameters: ["q": ["type": "string"]]) { args in
                let q = args["q"] as? String ?? ""
                guard !q.isEmpty else { return "q 缺失" }
                var out: [String] = []
                for file in Garden.listFiles(Garden.links) {
                    let url = Garden.links.appendingPathComponent(file)
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    if file.localizedCaseInsensitiveContains(q)
                        || text.localizedCaseInsensitiveContains(q) {
                        let target = text.split(separator: "\n")
                            .first { $0.hasPrefix("target:") }?
                            .dropFirst("target:".count)
                            .trimmingCharacters(in: .whitespaces) ?? ""
                        out.append("\(file)：\(target)")
                        if out.count >= 8 { break }
                    }
                }
                return out.isEmpty ? "（没搜到链接卡）" : out.joined(separator: "\n")
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
        用户忘了件事，你帮 ta 找线索。你有这些地方可以翻（花园是搜索的地基）：
        小传（search_moments）、最近的时间笔记（grep_notes / read_note）、
        人物卡（list_people / read_person）、链接卡（grep_links）、本机文件名（search_files）。
        方法：把问题拆成 2-3 个不同说法的关键词，中文用短词（1-2 字）逐个试；
        小传没有就翻笔记，涉及人就看人物卡，花园里都没有才搜本机文件。最多试六七次。
        找到了：用懒猫的口吻输出两行——第一行以「推理：」开头，一句话说线索怎么串起来的
        （顺口带上来自几号的笔记/小传）；第二行以「结论：」开头，一句话直接回答。
        不用 emoji，不给建议清单。严格按线索原文说，别脑补细节。
        实在没有：只输出一行「结论：」——诚实说没找到 + 猜一个最可能的去处。不要编造。
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

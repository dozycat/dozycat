import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
@preconcurrency import Vision

/// 原料层：高频（默认 45 秒）截**前台窗口** → 本机 Vision OCR（带位置）→
/// 聊天应用按气泡左右还原「谁说的什么」→ 去重后落 garden/raw/<日期>/<HHmmss>_raw.md。
///
/// 这是「一段一段」（sequence）的原始输入：OCR 是本机模型、不花钱，所以节奏可以
/// 远快于 5 分钟一次的模型调用；笔记里的每条事实都能 cite 回这里的原料段。
/// 人和人说的原话在这一层被原样留住——白描是后面的事，原料先说话。
///
/// 隐私：截图用后即删、OCR 全程本机；raw/ 在花园里，永不同步，14 天自动清理；
/// secure input（密码框）亮着、或前台是懒猫自己时跳过。
enum RawCapture {

    struct Segment {
        /// 花园相对路径（cite 用），如 raw/2026-08-08/110233_raw.md
        let ref: String
        let text: String
    }

    static var rawDir: URL { Garden.root.appendingPathComponent("raw") }

    // MARK: - 采一段

    /// 截前台窗口、OCR、结构化、落盘。返回写下的花园相对路径（没采到 = nil）。
    /// dedupe 闭包由 pump 提供（跟上一段比相似度，屏幕没变就不落重复原料）。
    static func captureOnce(dedupe: ([String]) -> Bool) async -> String? {
        // 密码框亮着不采；前台是懒猫自己不采
        guard !IsSecureEventInputEnabled() else { return nil }
        guard let window = frontWindow() else { return nil }

        let lines = await ocrLines(windowID: window.id)
        guard lines.count >= 3 else { return nil }
        guard dedupe(lines.map(\.text)) else { return nil }

        let isChat = ActivityClass.classify(app: window.app, bundleID: window.bundleID) == .comms
        let body = isChat ? chatTranscript(lines) : lines.map(\.text).joined(separator: "\n")
        guard !body.isEmpty else { return nil }

        let now = Date()
        let stamp = DateFormatter(); stamp.dateFormat = "HHmmss"
        let local = DateFormatter(); local.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let md = """
        ---
        time: \(local.string(from: now))（本地时间）
        app: \(window.app)
        window: \(window.title)
        kind: \(isChat ? "chat" : "screen")
        ---
        \(body)
        """
        let dir = rawDir.appendingPathComponent(Garden.day(now))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(stamp.string(from: now))_raw.md"
        let file = dir.appendingPathComponent(name)
        try? md.write(to: file, atomically: true, encoding: .utf8)
        return "raw/\(Garden.day(now))/\(name)"
    }

    /// 最近的原料段（「一段一段」5 分钟一跑时取的输入），按时间升序。
    static func segments(since: Date) -> [Segment] {
        let fm = FileManager.default
        var out: [(Date, Segment)] = []
        // 只需今天 + 昨天（跨零点的那一跑）
        for day in [Garden.day(), Garden.day(Date().addingTimeInterval(-86400))] {
            let dir = rawDir.appendingPathComponent(day)
            for name in Garden.listFiles(dir) where name.hasSuffix(".md") {
                let url = dir.appendingPathComponent(name)
                guard let mtime = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date,
                      mtime >= since,
                      let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                out.append((mtime, Segment(ref: "raw/\(day)/\(name)", text: text)))
            }
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// 原料只留最近 14 天——它是 cite 的地基，不是档案馆。
    static func prune(keepDays: Int = 14) {
        let fm = FileManager.default
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86400)
        for name in Garden.listFiles(rawDir) {
            if let day = f.date(from: name), day < cutoff {
                try? fm.removeItem(at: rawDir.appendingPathComponent(name))
            }
        }
    }

    // MARK: - 前台窗口

    private struct FrontWindow {
        let id: CGWindowID
        let app: String
        let bundleID: String
        let title: String
    }

    /// 前台 app 的主窗口（layer 0、够大的那一个）。窗口标题在聊天应用里
    /// 常常就是会话名（微信独立聊天窗的标题是联系人）。
    private static func frontWindow() -> FrontWindow? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid == front.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? UInt32 else { continue }
            if let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
               (bounds["Width"] ?? 0) < 320 || (bounds["Height"] ?? 0) < 220 { continue }
            return FrontWindow(id: CGWindowID(id),
                               app: front.localizedName ?? "",
                               bundleID: front.bundleIdentifier ?? "",
                               title: info[kCGWindowName as String] as? String ?? "")
        }
        return nil
    }

    // MARK: - OCR（带位置）

    struct Line {
        let text: String
        /// Vision 归一化坐标（原点左下）
        let box: CGRect
    }

    /// 前台窗口的像素（sequence 兜底 OCR 用），同样内存直采、不落盘。
    static func frontWindowImage() async -> CGImage? {
        guard let window = frontWindow() else { return nil }
        return await windowImage(windowID: window.id)
    }

    /// 这一个窗口的像素，直接取成内存里的 CGImage（ScreenCaptureKit）——
    /// **不落盘，没有截图文件存在过**，OCR 完即弃。权限同屏幕录制。
    static func windowImage(windowID: CGWindowID) async -> CGImage? {
        guard let content = try? await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID })
        else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // 2x 采样：OCR 的准确率吃分辨率
        config.width = Int(window.frame.width) * 2
        config.height = Int(window.frame.height) * 2
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                           configuration: config)
    }

    /// OCR 保留 boundingBox——气泡在窗口里的左右位置，就是「谁说的」的免费信号。
    private static func ocrLines(windowID: CGWindowID) async -> [Line] {
        guard let cg = await windowImage(windowID: windowID) else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?.compactMap { obs -> Line? in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return Line(text: top.string, box: obs.boundingBox)
                } ?? []
                continuation.resume(returning: lines)
            }
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.recognitionLevel = .accurate
            DispatchQueue.global(qos: .utility).async {
                let handler = VNImageRequestHandler(cgImage: cg)
                if (try? handler.perform([request])) == nil {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    // MARK: - 聊天还原

    /// 气泡左右 → 说话人。启发式，靠 -ocrProbe 对着真窗口核准：
    /// - 微信主窗左侧是会话列表，完全落在左 1/4 的行丢弃；
    /// - 离右边近的是右气泡（我），离左边近的是左气泡（对方）；
    /// - 居中的短行是时间戳/系统提示，降级为上下文行；
    /// - 连续同侧的行并成一条消息。
    static func chatTranscript(_ lines: [Line]) -> String {
        enum Side { case me, them, context }
        var messages: [(side: Side, text: String)] = []
        // 从上到下（Vision 原点在左下，y 大的在上面）
        for line in lines.sorted(by: { $0.box.midY > $1.box.midY }) {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let box = line.box
            if box.maxX < 0.25 { continue } // 会话列表 / 侧栏
            let side: Side
            if abs(box.midX - 0.5) < 0.09, box.width < 0.35, box.minX > 0.2 {
                side = .context // 时间戳、撤回提示这类居中短行
            } else if (1 - box.maxX) < box.minX {
                side = .me
            } else {
                side = .them
            }
            if side != .context, let last = messages.last, last.side == side {
                messages[messages.count - 1].text += " " + text
            } else {
                messages.append((side, text))
            }
        }
        return messages.map { m in
            switch m.side {
            case .me: "我：\(m.text)"
            case .them: "对方：\(m.text)"
            case .context: "· \(m.text)"
            }
        }.joined(separator: "\n")
    }

    // MARK: - 准确性核对（-ocrProbe <输出路径>）

    /// 把前台窗口的原始 OCR（带坐标）和聊天还原结果并排 dump 出来，
    /// 对着微信窗口跑一次，肉眼核对说话人归属和原话有没有认对。
    /// 启动后最多等 60 秒：把目标窗口（如微信）点到前台，它就采那一个——
    /// 刚 open 时前台是懒猫自己，得等用户切过去。
    static func probe(to path: String) async {
        var window: FrontWindow?
        for _ in 0..<60 {
            if let w = frontWindow() {
                window = w
                break
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard let window else {
            try? "（60 秒内没等到懒猫之外的前台窗口）".write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        let lines = await ocrLines(windowID: window.id)
        let rawDump = lines.sorted { $0.box.midY > $1.box.midY }.map { l in
            String(format: "x %.2f–%.2f  y %.2f  %@", l.box.minX, l.box.maxX, l.box.midY, l.text)
        }.joined(separator: "\n")
        let report = """
        # OCR 探针 · \(window.app) — \(window.title)

        ## 聊天还原（按气泡归属）
        \(chatTranscript(lines))

        ## 原始行（归一化坐标，从上到下）
        \(rawDump)
        """
        try? report.write(toFile: path, atomically: true, encoding: .utf8)
        NSLog("ocrProbe: \(lines.count) lines → \(path)")
    }
}

/// 采集泵：45 秒一拍（DOZYCAT_RAW_SECS 可调，0 = 关），人不在不采，
/// 屏幕没变不落盘（Jaccard ≥ 0.85 视为同一屏）。
@MainActor
final class RawCapturePump {
    static let shared = RawCapturePump()

    private var timer: Timer?
    private var lastLines: Set<String> = []
    private var busy = false

    func start() {
        let secs = ProcessInfo.processInfo.environment["DOZYCAT_RAW_SECS"]
            .flatMap(Double.init) ?? 45
        guard secs > 0, timer == nil else { return }
        RawCapture.prune()
        let t = Timer(timeInterval: secs, repeats: true) { _ in
            Task { @MainActor in await self.tick() }
        }
        t.tolerance = secs * 0.2
        RunLoop.main.add(t, forMode: .common)
    }

    private func tick() async {
        guard !busy else { return }
        // 人不在（上一分钟无输入）不采——省的不是钱是隐私面
        guard SenseFeed.shared.activeStreakMin > 0 else { return }
        busy = true
        defer { busy = false }
        _ = await RawCapture.captureOnce { [weak self] lines in
            guard let self else { return false }
            let new = Set(lines)
            let overlap = Double(new.intersection(self.lastLines).count)
            let union = Double(new.union(self.lastLines).count)
            let changed = union == 0 || overlap / union < 0.85
            if changed { self.lastLines = new }
            return changed
        }
    }
}

import AppKit

/// 微笑时刻：摄像头认出你笑了，就把那几秒屏幕上的文字（OCR）记进记事本——
/// 让懒猫记得是什么逗笑了你。
///
/// 频率与去重（不做这两件事，这功能就是垃圾制造机）：
/// - 表情 5 秒一拍，但两条微笑便签之间至少隔 3 分钟（冷却，环境变量
///   DOZYCAT_SMILE_COOLDOWN_SECS 可调）；
/// - 同一个乐子 30 分钟只记一次——和最近几条的 OCR 行集比 Jaccard，
///   ≥ 0.8 视为同屏内容，不重复记；
/// - 抓不到字（没给屏幕权限 / 密码框亮着 / 屏上没几行字）就安静放弃，
///   不写空便签。
///
/// 隐私走 RawCapture 的老边界：截图内存即弃、OCR 全程本机；完整原文落
/// garden/raw/（14 天自动清理，永不同步），便签里只留一行摘要 + 出处。
@MainActor
final class SmileMoments {
    static let shared = SmileMoments()

    private var lastNoteAt = Date.distantPast
    /// 最近几条微笑便签的 OCR 行集——短时间内容去重的比对底
    private var recent: [(at: Date, lines: Set<String>)] = []
    private var busy = false

    private let cooldown: TimeInterval
    private static let dedupeWindow: TimeInterval = 30 * 60
    private static let dedupeJaccard = 0.8
    private static let snippetLimit = 160

    private init() {
        cooldown = ProcessInfo.processInfo.environment["DOZYCAT_SMILE_COOLDOWN_SECS"]
            .flatMap(Double.init) ?? 180
    }

    /// 默认开——它依赖摄像头感知，那边不开这里根本不会被叫到。
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "smileMoments") as? Bool ?? true
    }

    /// PresenceSensor 的表情帧认出 happy（置信度够）时调用。
    func smiled() {
        guard Self.enabled, !busy,
              Date().timeIntervalSince(lastNoteAt) >= cooldown else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            await capture()
        }
    }

    private func capture() async {
        // 第一拍：笑的这一刻屏幕上是什么。屏幕内容以秒计基本不动，
        // 这一拍同时覆盖了「前几秒」。
        var firstLines: [String] = []
        guard let ref = await RawCapture.captureOnce(dedupe: { lines in
            firstLines = lines
            return true
        }) else { return }
        let lineSet = Set(firstLines)

        // 短时去重：同一个乐子（同一屏内容）30 分钟只记一次
        let now = Date()
        recent.removeAll { now.timeIntervalSince($0.at) > Self.dedupeWindow }
        for old in recent {
            let overlap = Double(lineSet.intersection(old.lines).count)
            let union = Double(lineSet.union(old.lines).count)
            if union > 0, overlap / union >= Self.dedupeJaccard { return }
        }

        // 第二拍：4 秒后再看一眼（「后几秒」——弹幕、对话可能刚好在翻页）。
        // 屏幕没变第二拍不落盘，摘要里也就没有新行可补。
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        var afterLines: [String] = []
        _ = await RawCapture.captureOnce(dedupe: { lines in
            afterLines = lines
            let new = Set(lines)
            let overlap = Double(new.intersection(lineSet).count)
            let union = Double(new.union(lineSet).count)
            return union == 0 || overlap / union < 0.85
        })

        guard let (app, snippet) = Self.digest(
            ref: ref, base: lineSet, after: afterLines) else { return }
        lastNoteAt = Date()
        recent.append((Date(), lineSet))
        let whereAt = app.isEmpty ? "" : "（\(app)）"
        NotesStore.shared.write("😊 笑了\(whereAt)：\(snippet)｜出处 \(ref)")
    }

    /// 出处文件 → (app, 摘要)。摘要 = 第一拍正文 + 第二拍新出现的行，截 160 字——
    /// 便签是给人和猫翻的，全文在 raw 里躺着。
    private static func digest(
        ref: String, base: Set<String>, after: [String]
    ) -> (app: String, snippet: String)? {
        let url = Garden.root.appendingPathComponent(ref)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var app = ""
        var body = text
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---\n") {
            for line in text[..<end.lowerBound].split(separator: "\n")
            where line.hasPrefix("app: ") {
                app = String(line.dropFirst(5))
            }
            body = String(text[end.upperBound...])
        }

        let fresh = after.filter { !base.contains($0) }
        var flat = (body.split(separator: "\n").map(String.init) + fresh)
            .joined(separator: " / ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flat.isEmpty else { return nil }
        if flat.count > snippetLimit {
            flat = String(flat.prefix(snippetLimit)) + "…"
        }
        return (app, flat)
    }
}

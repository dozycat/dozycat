import AppKit
import AVFoundation
@preconcurrency import Vision

/// 疲劳感知的语义提示（v2）：pet 侧产出两枚原子——摄像头在位布尔 + 活动类别——
/// 写进 ~/.dozycat/sense_hints.json，dozycat-sense 每分钟带保鲜期地读。
///
/// 隐私边界（对齐 docs/FATIGUE.md）：摄像头帧在内存里过一遍人脸检测就丢，
/// 不落盘不出进程，跨过文件边界的只有 true/false；OCR 文本留在 sequence 管线，
/// 跨过边界的只有六选一的类别标签。
enum ActivityClass: String {
    case unknown, deep, comms, meeting, browse, fun

    /// 规则分类：前台 app 名/bundle id 先判，浏览器里的会议和视频靠 OCR 关键词兜。
    /// 分不清就 unknown——模型对 unknown 退回 v0 语义，宁缺毋滥。
    static func classify(app: String, bundleID: String, ocr: String = "") -> ActivityClass {
        let a = (app + " " + bundleID).lowercased()

        func hit(_ needles: [String], in text: String) -> Bool {
            needles.contains { text.contains($0) }
        }

        // 会议优先：开会时前台常是会议 app，但浏览器开会要靠页面文字认
        if hit(["zoom", "teams", "facetime", "webex", "腾讯会议", "voovmeeting", "voov meeting"], in: a) {
            return .meeting
        }
        let lowOCR = ocr.lowercased()
        if !ocr.isEmpty, hit(["google meet", "腾讯会议", "共享屏幕", "参会者", "静音", "结束会议"], in: lowOCR),
           hit(["safari", "chrome", "arc", "firefox", "edge", "browser"], in: a) {
            return .meeting
        }

        if hit(["微信", "wechat", "qq", "telegram", "slack", "discord", "whatsapp",
                "钉钉", "dingtalk", "飞书", "lark", "messages", "com.apple.mail",
                "spark", "outlook"], in: a) {
            return .comms
        }

        if hit(["xcode", "cursor", "com.microsoft.vscode", "visual studio", "iterm",
                "terminal", "intellij", "pycharm", "goland", "clion", "webstorm",
                "sublime", "zed", "emacs", "neovim", "typora", "obsidian",
                "pages", "com.microsoft.word"], in: a) {
            return .deep
        }

        if hit(["iina", "vlc", "quicktime", "steam", "crossover", "优酷", "爱奇艺",
                "腾讯视频", "bilibili", "netflix", "infuse", "tv.danmaku"], in: a) {
            return .fun
        }

        if hit(["safari", "chrome", "arc", "firefox", "edge"], in: a) {
            // 浏览器里在看什么，页面文字比 app 名诚实
            if !ocr.isEmpty, hit(["bilibili", "哔哩", "youtube", "netflix", "弹幕",
                                  "番剧", "直播", "爱奇艺", "腾讯视频"], in: lowOCR) {
                return .fun
            }
            return .browse
        }

        return .unknown
    }
}

/// hints 文件的单写者：30 秒一拍（前台 app 的 app 级分类 + 摄像头在位），
/// sequence 每 5 分钟带 OCR 的精分类到了就覆盖。
@MainActor
final class SenseHintsPump {
    static let shared = SenseHintsPump()

    private var timer: Timer?
    private var present: (value: Bool, at: Date)?
    private var activity: (value: ActivityClass, at: Date) = (.unknown, .distantPast)

    private static var hintsURL: URL {
        if let p = ProcessInfo.processInfo.environment["DOZYCAT_HINTS"] {
            return URL(fileURLWithPath: p)
        }
        return URL(fileURLWithPath: NSHomeDirectory() + "/.dozycat/sense_hints.json")
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { _ in
            Task { @MainActor in self.tick() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        tick()
    }

    private func tick() {
        // app 级活动分类，每 30 秒免费拿一档；OCR 精分类由 SequenceAgent 覆盖
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            let cls = ActivityClass.classify(app: front?.localizedName ?? "",
                                             bundleID: front?.bundleIdentifier ?? "")
            if cls != .unknown {
                activity = (cls, Date())
            }
        }
        PresenceSensor.shared.sampleIfEnabled { [weak self] present in
            guard let self else { return }
            if let present { self.present = (present, Date()) }
            self.flush()
        }
    }

    /// sequence 的 OCR 精分类入口（带页面文字，浏览器里的会议/视频认得出）。
    func updateActivity(_ cls: ActivityClass) {
        guard cls != .unknown else { return }
        activity = (cls, Date())
        flush()
    }

    private func flush() {
        var fields: [String] = []
        if let present {
            fields.append("\"present\":\(present.value)")
            fields.append("\"presentAtMs\":\(Int64(present.at.timeIntervalSince1970 * 1000))")
        }
        if activity.value != .unknown {
            fields.append("\"activity\":\"\(activity.value.rawValue)\"")
            fields.append("\"activityAtMs\":\(Int64(activity.at.timeIntervalSince1970 * 1000))")
        }
        let json = "{" + fields.joined(separator: ",") + "}"
        try? FileManager.default.createDirectory(
            at: Self.hintsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? json.write(to: Self.hintsURL, atomically: true, encoding: .utf8)
    }
}

/// 摄像头在位：低分辨率常开会话，30 秒抽一帧过 Vision 人脸检测。
/// 帧只在内存里活到检测完，没有截图、没有落盘；开启期间摄像头指示灯常亮——
/// 这是诚实的代价，设置里写明。默认关。
final class PresenceSensor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = PresenceSensor()

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dozycat.presence", qos: .utility)
    private var configured = false
    private var lastDetection = Date.distantPast
    /// 最近一次检测结果（nil = 还没有 / 未开启）
    private var lastPresent: Bool?
    private var pendingCallback: (@MainActor @Sendable (Bool?) -> Void)?

    var enabled: Bool {
        UserDefaults.standard.bool(forKey: "presenceSensing")
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "presenceSensing")
        if on {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else { return }
                self.queue.async { self.startSession() }
            }
        } else {
            queue.async {
                if self.session.isRunning { self.session.stopRunning() }
                self.lastPresent = nil
            }
        }
    }

    /// SenseHintsPump 的 30s tick 入口：回调最近的在位判定（未开启回 nil）。
    func sampleIfEnabled(_ callback: @escaping @MainActor @Sendable (Bool?) -> Void) {
        guard enabled else {
            Task { @MainActor in callback(nil) }
            return
        }
        queue.async {
            if !self.session.isRunning { self.startSession() }
            let value = self.lastPresent
            Task { @MainActor in callback(value) }
        }
    }

    private func startSession() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        if !configured {
            configured = true
            session.sessionPreset = .vga640x480
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        if !session.isRunning { session.startRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // 30 秒抽一帧就够——在位状态的变化尺度是分钟级
        guard Date().timeIntervalSince(lastDetection) >= 30,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastDetection = Date()
        let request = VNDetectFaceRectanglesRequest { [weak self] req, _ in
            let faces = (req.results as? [VNFaceObservation]) ?? []
            self?.lastPresent = !faces.isEmpty
        }
        // 帧的生命周期到这里为止：检测完即弃，不留任何图像数据
        try? VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([request])
    }
}

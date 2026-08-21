import AppKit
import AVFoundation
import Combine
@preconcurrency import Vision

/// 疲劳感知的语义提示（v2）：pet 侧产出两枚原子——摄像头在位布尔 + 活动类别——
/// 写进 ~/.dozycat/sense_hints.json，dozycat-sense 每分钟带保鲜期地读。
///
/// 隐私边界（对齐 docs/FATIGUE.md）：摄像头帧在内存里过一遍人脸检测 + 表情
/// 分类就丢，不落盘不出进程，跨过文件边界的只有在/不在的 true/false 和一个
/// 七选一的表情标签（happy/sad 这类词，模型在本地，见 model/emotion/）；
/// OCR 文本留在 sequence 管线，跨过边界的只有六选一的类别标签。
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
    private var mood: (value: Emotion, at: Date)?
    private var activity: (value: ActivityClass, at: Date) = (.unknown, .distantPast)

    private static var hintsURL: URL {
        if let p = ProcessInfo.processInfo.environment["DOZYCAT_HINTS"] {
            return URL(fileURLWithPath: p)
        }
        return AppPaths.file("sense_hints.json")
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
        PresenceSensor.shared.sampleIfEnabled { [weak self] present, mood in
            guard let self else { return }
            if let present { self.present = (present, Date()) }
            if let mood { self.mood = (mood, Date()) }
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
        if let mood {
            fields.append("\"mood\":\"\(mood.value.rawValue)\"")
            fields.append("\"moodAtMs\":\(Int64(mood.at.timeIntervalSince1970 * 1000))")
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

/// 摄像头在位 + 表情：低分辨率常开会话，30 秒抽一帧过 Vision 人脸检测，
/// 有脸再过一遍本地表情小模型（EmotionNet，222KB）。帧只在内存里活到推理完，
/// 没有截图、没有落盘；开启期间摄像头指示灯常亮——这是诚实的代价，设置里写明。
/// 默认关。
final class PresenceSensor: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = PresenceSensor()

    enum Status: Equatable {
        case disabled
        case starting
        case running
        case permissionDenied
        case cameraUnavailable
        case failed
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dozycat.presence", qos: .utility)
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sessionStartedAt: Date?
    private var lastFrameAt: Date?
    private var lastDetection = Date.distantPast
    /// 最近一次检测结果（nil = 还没有 / 未开启）
    private var lastPresent: Bool?
    /// 最近一次表情判定（nil = 没脸 / 置信度不够 / 模型没加载）
    private var lastMood: Emotion?
    /// 懒加载：第一次用到才从 bundle 读权重；加载失败就一直是 nil，在位感知照常
    private lazy var emotionClassifier: EmotionClassifier? = EmotionClassifier()

    /// 开关表示用户意愿；这里才是摄像头是否真的开始交付画面。
    /// 所有写入都经主线程，供设置页安全观察。
    @Published private(set) var status: Status = .disabled

    var enabled: Bool {
        UserDefaults.standard.bool(forKey: "presenceSensing")
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "presenceSensing")
        if on {
            requestPermissionAndStart()
        } else {
            queue.async {
                if self.session.isRunning { self.session.stopRunning() }
                self.sessionStartedAt = nil
                self.lastFrameAt = nil
                self.lastPresent = nil
                self.lastMood = nil
                self.publish(.disabled)
            }
        }
    }

    /// 从系统设置回到懒猫时再查一次。用户把残留的旧 TCC 条目关闭再打开后，
    /// 不必再次拨动产品开关，会话会立刻按新的授权状态启动。
    func retryIfEnabled() {
        guard enabled else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            publish(.permissionDenied)
            return
        }
        queue.async { self.ensureSession() }
    }

    private func requestPermissionAndStart() {
        publish(.starting)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.ensureSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else {
                    self.publish(.permissionDenied)
                    return
                }
                self.queue.async { self.ensureSession() }
            }
        case .denied, .restricted:
            publish(.permissionDenied)
        @unknown default:
            publish(.failed)
        }
    }

    /// SenseHintsPump 的 30s tick 入口：回调最近的在位 + 表情判定（未开启回 nil）。
    func sampleIfEnabled(_ callback: @escaping @MainActor @Sendable (Bool?, Emotion?) -> Void) {
        guard enabled else {
            Task { @MainActor in callback(nil, nil) }
            return
        }
        queue.async {
            self.ensureSession()
            let present = self.lastPresent
            let mood = self.lastMood
            Task { @MainActor in callback(present, mood) }
        }
    }

    /// 确保会话不只是 `isRunning`，而且最近真的收到过帧。设备断开、合盖或
    /// AVFoundation 偶发进入「运行但零帧」时，下一拍会拆掉旧输入再建一次。
    private func ensureSession() {
        guard enabled else {
            publish(.disabled)
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            NSLog("PresenceSensor: camera permission is not authorized (%ld)",
                  AVCaptureDevice.authorizationStatus(for: .video).rawValue)
            publish(.permissionDenied)
            return
        }

        let now = Date()
        if session.isRunning {
            let lastDelivery = lastFrameAt ?? sessionStartedAt ?? .distantPast
            if now.timeIntervalSince(lastDelivery) < 12 { return }
            NSLog("PresenceSensor: capture stalled; rebuilding camera input")
            session.stopRunning()
            sessionStartedAt = nil
            lastFrameAt = nil
            removeInputs()
        }

        publish(.starting)
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        if videoOutput == nil {
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                NSLog("PresenceSensor: cannot add video output")
                publish(.failed)
                return
            }
            session.addOutput(output)
            videoOutput = output
        }

        // `session.inputs` 里可能残留已经断开的设备；只判断 isEmpty 会让会话
        // 永久卡在 running-but-no-frames。每次重启都明确换成当前连接的设备。
        removeInputs()
        guard let device = Self.pickCamera() else {
            session.commitConfiguration()
            NSLog("PresenceSensor: no connected built-in or external camera")
            publish(.cameraUnavailable)
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                NSLog("PresenceSensor: cannot add camera input %@", device.localizedName)
                publish(.failed)
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            NSLog("PresenceSensor: camera input failed: %@", error.localizedDescription)
            publish(.failed)
            return
        }
        session.commitConfiguration()

        session.startRunning()
        guard session.isRunning else {
            NSLog("PresenceSensor: AVCaptureSession did not start")
            publish(.failed)
            return
        }
        sessionStartedAt = Date()
        NSLog("PresenceSensor: waiting for first frame from %@", device.localizedName)

        // isRunning 只说明 session graph 启动，不保证摄像头交付了画面。
        // 五秒仍无首帧就公开失败状态；30 秒 pump 会自动重新建输入再试。
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.enabled, self.session.isRunning,
                  self.lastFrameAt == nil else { return }
            NSLog("PresenceSensor: session is running but delivered no frames")
            self.publish(.failed)
        }
    }

    private func removeInputs() {
        for input in session.inputs {
            session.removeInput(input)
        }
    }

    /// 只用内置或有线外接摄像头。刻意不碰 Continuity Camera——为了看你在不在
    /// 而悄悄点亮你手机的摄像头，太吓人了。
    private static func pickCamera() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video, position: .unspecified)
        let devices = discovery.devices.filter(\.isConnected)
        return devices.first { $0.deviceType == .builtInWideAngleCamera } ?? devices.first
    }

    private func publish(_ newStatus: Status) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.status != newStatus else { return }
            self.status = newStatus
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let isFirstFrame = lastFrameAt == nil
        lastFrameAt = Date()
        if isFirstFrame {
            NSLog("PresenceSensor: first camera frame received")
            publish(.running)
        }
        // 5 秒抽一帧：在位状态是分钟级的，但微笑转瞬即逝，30 秒一拍会漏掉大半。
        // 人脸检测 + 6 万参数的小模型，5 秒一次的开销是毫秒级，可以承受。
        guard Date().timeIntervalSince(lastDetection) >= 5,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastDetection = Date()
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([request])
        let faces = request.results ?? []
        lastPresent = !faces.isEmpty
        // 有脸就顺手认一下表情：取最大的脸（屏幕前的人），置信度不够记 nil
        if let face = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) {
            let mood = emotionClassifier?.classify(pixelBuffer: pixels, face: face)
            lastMood = mood?.0
            // 笑了（置信度要够高，别把嘴角的错觉当成乐子）→ 微笑时刻去看一眼屏幕。
            // 冷却和去重都在 SmileMoments 里，这里只管报信。
            if let mood, mood.0 == .happy, mood.1 >= 0.6 {
                Task { @MainActor in SmileMoments.shared.smiled() }
            }
        } else {
            lastMood = nil
        }
        // 帧的生命周期到这里为止：推理完即弃，不留任何图像数据
    }
}

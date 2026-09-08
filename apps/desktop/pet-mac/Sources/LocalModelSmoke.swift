#if DEBUG
import AppKit

/// Opt-in, isolated integration check. No screenshot capture or real user tools.
@MainActor
enum LocalModelSmoke {
    static func run(reportURL: URL) async {
        let model = ProcessInfo.processInfo.environment["DOZYCAT_MLX_MODEL"] ?? LocalModelStore.supportedIDs[0]
        let config = LLMClient.Config(baseURL: LocalModelStore.directory(for: model), model: model,
                                     apiKey: "", localModelDirectory: LocalModelStore.directory(for: model))
        var peak: UInt64 = 0
        let sample = Task {
            while !Task.isCancelled {
                peak = max(peak, LocalMemory.footprint)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        var checks: [[String: Any]] = []
        let started = Date()
        var failure: String?
        do {
            let hello = try await LLMClient.reply(history: [("user", "我工作了一上午有点累，请用一句中文陪我聊聊。")], config: config)
            checks.append(["name": "chinese_chat", "reply": hello, "passed": !hello.isEmpty])

            async let first = LLMClient.reply(history: [("user", "只回复：甲")], config: config)
            async let second = LLMClient.reply(history: [("user", "只回复：乙")], config: config)
            let pair = try await (first, second)
            checks.append(["name": "concurrent_requests", "replies": [pair.0, pair.1],
                           "passed": pair.0.contains("甲") && pair.1.contains("乙")])

            let space = CGColorSpaceCreateDeviceRGB()
            let canvas = CGContext(data: nil, width: 448, height: 448, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            canvas.setFillColor(NSColor.white.cgColor)
            canvas.fill(CGRect(x: 0, y: 0, width: 448, height: 448))
            canvas.setFillColor(NSColor.red.cgColor)
            canvas.fillEllipse(in: CGRect(x: 100, y: 100, width: 248, height: 248))
            let image = NSBitmapImageRep(cgImage: canvas.makeImage()!).representation(using: .png, properties: [:])!
            for iteration in 1...3 {
                var observations: [String] = []
                let tool = AgentTool(name: "record_observation", description: "记录图片中主要形状的颜色，返回验证口令。",
                                     parameters: ["color": ["type": "string", "description": "图片形状的颜色，中文"]], requiredParameters: ["color"]) { args in
                    observations.append(args["color"] as? String ?? "")
                    return "验证口令是 LOCAL_TOOL_OK_742"
                }
                let answer = try await PiAgent.run(
                    system: "你是图片记录助手。必须先调用 record_observation 记录图片的主要形状颜色，再原样回复工具返回的验证口令。",
                    history: [("user", "请看图，记录颜色，并告诉我验证口令。")], tools: [tool], config: config,
                    imageData: image)
                checks.append(["name": "vision_tool_roundtrip_\(iteration)", "reply": answer,
                               "observations": observations,
                               "passed": observations.contains(where: { $0.contains("红") || $0.lowercased().contains("red") }) && answer.contains("LOCAL_TOOL_OK_742")])
            }
            do {
                _ = try await LLMClient.reply(history: [("user", String(repeating: "这是无法放进上下文的一段内容。", count: 1000))], config: config)
                checks.append(["name": "context_budget", "passed": false])
            } catch LocalModelError.contextTooLong {
                checks.append(["name": "context_budget", "passed": true])
            }
        } catch { failure = String(describing: error) + ": " + error.localizedDescription }
        sample.cancel()
        await sample.value
        peak = max(peak, LocalMemory.footprint)
        var report: [String: Any] = ["model": model, "peak_footprint_bytes": peak,
                                    "duration_seconds": Date().timeIntervalSince(started), "checks": checks,
                                    "passed": failure == nil && !checks.isEmpty && checks.allSatisfy { $0["passed"] as? Bool == true } && peak < 6_000_000_000]
        if let failure { report["error"] = failure }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: reportURL, options: .atomic)
        }
        NSApp.terminate(nil)
    }
}
#endif

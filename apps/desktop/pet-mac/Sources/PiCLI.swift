import Foundation

/// 真 pi 执行器：spawn 本机的 `pi` CLI（session 落 ~/.pi/agent/sessions，
/// 在 pi 的 session 浏览器里可见）。dream/searcher 直接用 pi 自带的
/// read/bash/edit/write 工具跑在 garden 目录上；找不到 pi 时上层回退
/// 到内置的 Swift 工具循环（PiAgent）。
@MainActor
enum PiCLI {
    static let binPath: String? = locate()
    static var available: Bool { binPath != nil && providerArgs() != nil }

    /// 跑一回合。`sessionID` 非空则持久续聊（chat 用）；`ephemeral` 不留 session（sequence 用）。
    static func run(name: String,
                    system: String,
                    prompt: String,
                    cwd: URL? = nil,
                    sessionID: String? = nil,
                    ephemeral: Bool = false,
                    timeout: TimeInterval = 300) async -> String? {
        guard let bin = binPath, let provider = providerArgs() else { return nil }
        var args = ["-p", "--mode", "text",
                    "--provider", provider.name, "--model", provider.model,
                    "--system-prompt", system,
                    "--name", name]
        if let sessionID { args += ["--session-id", sessionID] }
        if ephemeral { args.append("--no-session") }
        args.append(prompt)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env[provider.keyEnv] = provider.key
        // pi 是 node 脚本（#!/usr/bin/env node）：node 得在 PATH 里
        let binDir = (bin as NSString).deletingLastPathComponent
        env["PATH"] = binDir + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline { usleep(200_000) }
                if process.isRunning { process.terminate() }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text.isEmpty ? nil : text)
            }
        }
    }

    // MARK: provider 映射（BYOK 设置 → pi 的 provider/env）

    private struct ProviderArgs {
        let name: String
        let model: String
        let key: String
        let keyEnv: String
    }

    private static func providerArgs() -> ProviderArgs? {
        guard let config = SettingsStore.shared.llmConfig else { return nil }
        switch SettingsStore.shared.provider {
        case .deepseek:
            return ProviderArgs(name: "deepseek", model: config.model,
                                key: config.apiKey, keyEnv: "DEEPSEEK_API_KEY")
        case .openai:
            return ProviderArgs(name: "openai", model: config.model,
                                key: config.apiKey, keyEnv: "OPENAI_API_KEY")
        case .custom:
            return nil // 自定义端点走内置循环
        }
    }

    private static func locate() -> String? {
        if let override = ProcessInfo.processInfo.environment["DOZYCAT_PI_BIN"],
           FileManager.default.isExecutableFile(atPath: override) { return override }
        var candidates = ["/opt/homebrew/bin/pi", "/usr/local/bin/pi",
                          NSHomeDirectory() + "/.local/bin/pi"]
        // fnm 安装的 node 版本目录
        let fnm = NSHomeDirectory() + "/.local/share/fnm/node-versions"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: fnm) {
            candidates += versions.map { "\(fnm)/\($0)/installation/bin/pi" }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// 小传交接：pi 跑在 garden 里，往 moments_inbox.jsonl 追加行；
/// 跑完由 pet（store 单写者）统一入库。
@MainActor
enum MomentsBridge {
    static var inbox: URL { Garden.root.appendingPathComponent("moments_inbox.jsonl") }
    static var snapshot: URL { Garden.root.appendingPathComponent("moments_snapshot.md") }

    /// 给 agent 读的小传快照（store 是二进制，agent 用不了；grep 用这个）。
    static func writeSnapshot() {
        let lines = PetStore.shared.recent(limit: 200)
            .map { "- \($0.source)：\($0.text)\($0.note.map { "（\($0)）" } ?? "")" }
        try? ("# 小传快照（只读，由懒猫维护）\n\n" + lines.joined(separator: "\n"))
            .write(to: snapshot, atomically: true, encoding: .utf8)
    }

    /// 收 inbox：逐行 JSON {"text","note"}，≤3 条/天在这里兜底。
    @discardableResult
    static func ingest() -> [String] {
        guard let raw = try? String(contentsOf: inbox, encoding: .utf8) else { return [] }
        try? FileManager.default.removeItem(at: inbox)
        var saved: [String] = []
        for line in raw.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let text = obj["text"] as? String, !text.isEmpty else { continue }
            let todayCount = PetStore.shared.recent(limit: 50)
                .filter { $0.source.hasPrefix(String(localized: "今天")) }.count
            guard todayCount < 3 else { break }
            PetStore.shared.addMemory(text: text, note: obj["note"] as? String)
            saved.append(text)
        }
        writeSnapshot()
        return saved
    }

    /// 各 agent 的 system prompt 里共用的「怎么存小传」说明。
    static let howToSave = """
    要把一件值得记住的小事存进用户小传时，往当前目录的 moments_inbox.jsonl 追加一行 JSON：
    {"text":"第三人称白描，≤40字","note":"两三个字的情绪词 · 可选跟进"}
    （用 bash 的 echo '...' >> moments_inbox.jsonl）。宁缺毋滥，一天最多 3 条。
    已有的小传在 moments_snapshot.md 里，可先看避免重复。
    """
}

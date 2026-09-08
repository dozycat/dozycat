import Foundation
import SwiftUI

/// Installation is explicit; generation never contacts a model hub.
@MainActor
final class LocalModelStore: ObservableObject {
    static let shared = LocalModelStore()
    nonisolated static let supportedIDs = [
        "mlx-community/Qwen3.5-4B-4bit", "mlx-community/Qwen3.5-2B-4bit"
    ]
    @Published private(set) var downloading = false
    @Published private(set) var status = ""
    @Published private(set) var completedFiles = 0
    @Published private(set) var totalFiles = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published private(set) var totalBytes: Int64 = 0
    private var downloadTask: Task<Void, Never>?

    nonisolated static func directory(for id: String) -> URL {
        AppPaths.directory("models").appendingPathComponent(id.replacingOccurrences(of: "/", with: "--"))
    }

    nonisolated static func isInstalled(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: directory(for: id).appendingPathComponent("installation.json").path)
    }

    func cancel() { downloadTask?.cancel() }

    func download(_ id: String) {
        guard !downloading, Self.supportedIDs.contains(id) else { return }
        downloading = true
        completedFiles = 0
        totalFiles = 0
        downloadedBytes = 0
        totalBytes = 0
        status = "正在获取模型信息…"
        downloadTask = Task {
            defer { downloading = false; downloadTask = nil }
            let destination = Self.directory(for: id)
            let staging = destination.appendingPathExtension("partial")
            let cache = AppPaths.directory("downloads").appendingPathComponent(id.replacingOccurrences(of: "/", with: "--"))
            do {
                let fm = FileManager.default
                if Self.isInstalled(id) { status = "模型已下载，可离线使用"; return }
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 30 // inactivity, not total transfer time
                configuration.timeoutIntervalForResource = 3600
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                try await LocalModelDownloadSource.withFallback { source in
                    if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
                    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                    completedFiles = 0
                    totalFiles = 0
                    downloadedBytes = 0
                    totalBytes = 0
                    status = source == .huggingFace ? "正在连接 Hugging Face…" : "正在自动切换到魔搭 ModelScope…"
                    let manifest = try await source.manifest(for: id, session: session)
                    totalFiles = manifest.files.count
                    totalBytes = manifest.files.reduce(0) { $0 + $1.size }
                    var finishedBytes: Int64 = 0
                    for file in manifest.files {
                        try Task.checkCancellation()
                        status = "\(source.label)：\(file.name)（\(completedFiles + 1)/\(totalFiles)）"
                        let base = finishedBytes
                        let cached = try await LocalModelTransfer.download(file, session: session, cacheDirectory: cache) { bytes in
                            await MainActor.run { self.downloadedBytes = base + bytes }
                        }
                        try Task.checkCancellation()
                        // Same filesystem: a hard link avoids duplicating multi-GB weights.
                        try fm.linkItem(at: cached, to: staging.appendingPathComponent(file.name))
                        finishedBytes += file.size
                        downloadedBytes = finishedBytes
                        completedFiles += 1
                    }
                    try Task.checkCancellation()
                    let marker = try JSONSerialization.data(withJSONObject: [
                        "model": id, "source": source.rawValue,
                        "files": manifest.files.map { ["name": $0.name, "revision": $0.revision] }
                    ])
                    try marker.write(to: staging.appendingPathComponent("installation.json"), options: .atomic)
                }
                try Task.checkCancellation()
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: staging, to: destination)
                try? fm.removeItem(at: cache)
                status = "模型已下载，可离线使用"
            } catch {
                try? FileManager.default.removeItem(at: staging)
                status = Task.isCancelled ? "下载已暂停，再次点击下载可继续" : "下载失败：\(error.localizedDescription)"
            }
        }
    }
}

enum LocalModelError: LocalizedError {
    case notInstalled, invalidDownload, contextTooLong, invalidImage, invalidToolCall, memoryBudget
    var errorDescription: String? {
        switch self {
        case .notInstalled: "请先在设置的「本地 MLX」中下载模型。"
        case .invalidDownload: "模型文件下载不完整或服务不可用，请重试。"
        case .contextTooLong: "内容超过本地模型的 4K 上下文预算，请缩短输入。"
        case .invalidImage: "无法读取图片，请换一张图片。"
        case .invalidToolCall: "本地模型返回了无效的工具调用，请重试。"
        case .memoryBudget: "内存接近 6GB 预算，请切换到 2B 模型或缩短输入。"
        }
    }
}

struct LocalModelControls: View {
    @ObservedObject private var store = LocalModelStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    private var modelID: String { settings.model.isEmpty ? LLMProvider.localMLX.defaultModel : settings.model }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("本地模型", selection: $settings.model) {
                Text("Qwen3.5 4B · 效果优先 · 约 3.1GB 下载").tag("")
                Text("Qwen3.5 2B · 低内存 · 约 1.8GB 下载").tag(LocalModelStore.supportedIDs[1])
            }
            .disabled(store.downloading)
            Text("默认从 Hugging Face 下载，失败时自动切换到魔搭国内源。")
                .font(.caption).foregroundStyle(DS.muted)
            HStack {
                Button(LocalModelStore.isInstalled(modelID) ? "已下载" : "下载模型") { store.download(modelID) }
                    .disabled(store.downloading || LocalModelStore.isInstalled(modelID))
                if store.downloading {
                    ProgressView().controlSize(.small)
                    Button("暂停") { store.cancel() }
                }
            }
            if store.downloading && store.totalBytes > 0 {
                ProgressView(value: Double(store.downloadedBytes), total: Double(store.totalBytes))
                Text("\(ByteCountFormatter.string(fromByteCount: store.downloadedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: store.totalBytes, countStyle: .file))")
                    .font(.caption).foregroundStyle(DS.muted)
            }
            if !store.status.isEmpty { Text(store.status).font(.caption).textSelection(.enabled) }
            Text("下载后可断网使用，图片和对话在本机处理。目标峰值内存 6GB 以内；4K 上下文，单张图片。")
                .font(.caption).foregroundStyle(DS.muted)
        }
    }
}

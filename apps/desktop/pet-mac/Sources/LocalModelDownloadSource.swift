import Foundation
import CryptoKit

/// Each attempt resolves and downloads a complete snapshot from one provider.
/// A failed attempt is discarded before switching providers; revisions never mix.
enum LocalModelDownloadSource: String, CaseIterable, Sendable {
    case huggingFace, modelScope
    var label: String { self == .huggingFace ? "Hugging Face" : "魔搭 ModelScope" }

    static func withFallback<Result>(_ operation: (Self) async throws -> Result) async throws -> Result {
        var failures: [String] = []
        for source in [Self.huggingFace, .modelScope] {
            try Task.checkCancellation()
            do { return try await operation(source) }
            catch {
                if error is CancellationError { throw error }
                if let urlError = error as? URLError, urlError.code == .cancelled { throw error }
                try Task.checkCancellation()
                failures.append("\(source.label)：\(error.localizedDescription)")
            }
        }
        throw NSError(domain: "LocalModelDownload", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "；")])
    }

    struct File: Sendable {
        let name: String
        let url: URL
        let revision: String
        let size: Int64
        let sha256: String?

        func verify(at url: URL) throws {
            let actual = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            guard actual?.int64Value == size else { throw DownloadError.invalidFile }
            if let sha256 {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var digest = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    digest.update(data: chunk)
                }
                let hex = digest.finalize().map { String(format: "%02x", $0) }.joined()
                guard hex == sha256 else { throw DownloadError.invalidFile }
            }
        }
    }
    struct Manifest: Sendable {
        let files: [File]
    }
    enum DownloadError: LocalizedError {
        case invalidResponse, invalidFile
        var errorDescription: String? {
            switch self {
            case .invalidResponse: "模型下载源暂不可用。"
            case .invalidFile: "模型文件不完整或校验失败。"
            }
        }
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DownloadError.invalidResponse
        }
    }

    private static func modelFile(_ name: String) -> Bool {
        !name.contains("/") && !name.hasPrefix(".") && name != "installation.json"
            && (name.hasSuffix(".json") || name.hasSuffix(".safetensors") || name.hasSuffix(".jinja") || name == "merges.txt")
    }
    private static func validRevision(_ revision: String) -> Bool {
        revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil
    }

    func manifest(for id: String, session: URLSession) async throws -> Manifest {
        // Model ids come from the fixed in-app catalog, never arbitrary URLs.
        guard ["mlx-community/Qwen3.5-4B-4bit", "mlx-community/Qwen3.5-2B-4bit"].contains(id) else {
            throw DownloadError.invalidResponse
        }
        let endpoint: String
        switch self {
        case .huggingFace: endpoint = "https://huggingface.co/api/models/\(id)?blobs=true"
        case .modelScope: endpoint = "https://modelscope.cn/api/v1/models/\(id)/repo/files?Revision=master&Recursive=true"
        }
        let (data, response) = try await session.data(for: URLRequest(url: URL(string: endpoint)!, timeoutInterval: 15))
        try Self.check(response)
        let files: [File]
        switch self {
        case .huggingFace:
            struct Repository: Decodable {
                struct Entry: Decodable {
                    struct LFS: Decodable { let sha256: String }
                    let rfilename: String
                    let size: Int64
                    let lfs: LFS?
                }
                let sha: String
                let siblings: [Entry]
            }
            let repo = try JSONDecoder().decode(Repository.self, from: data)
            guard Self.validRevision(repo.sha) else { throw DownloadError.invalidResponse }
            files = repo.siblings.filter { Self.modelFile($0.rfilename) }.map {
                File(name: $0.rfilename, url: URL(string: "https://huggingface.co/\(id)/resolve/\(repo.sha)/\($0.rfilename)")!,
                     revision: repo.sha, size: $0.size, sha256: $0.lfs?.sha256)
            }
        case .modelScope:
            struct Response: Decodable {
                struct Payload: Decodable {
                    struct Entry: Decodable {
                        let Path: String
                        let Revision: String
                        let Size: Int64
                        let Sha256: String
                        let `Type`: String
                    }
                    let Files: [Entry]
                }
                let Code: Int
                let Data: Payload
            }
            let repo = try JSONDecoder().decode(Response.self, from: data)
            guard repo.Code == 200 else { throw DownloadError.invalidResponse }
            files = try repo.Data.Files.filter { $0.Type == "blob" && Self.modelFile($0.Path) }.map {
                guard Self.validRevision($0.Revision) else { throw DownloadError.invalidResponse }
                var url = URLComponents(string: "https://modelscope.cn/api/v1/models/\(id)/repo")!
                url.queryItems = [.init(name: "Revision", value: $0.Revision), .init(name: "FilePath", value: $0.Path)]
                return File(name: $0.Path, url: url.url!, revision: $0.Revision, size: $0.Size, sha256: $0.Sha256)
            }
        }
        guard Set(files.map(\.name)).count == files.count,
              files.contains(where: { $0.name == "config.json" }),
              files.contains(where: { $0.name == "tokenizer.json" }),
              files.contains(where: { $0.name.hasSuffix(".safetensors") }),
              files.allSatisfy({ $0.size > 0 && $0.size < 4_000_000_000 }),
              files.allSatisfy({ file in
                  guard let hash = file.sha256 else { return !file.name.hasSuffix(".safetensors") }
                  return hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
              }) else { throw DownloadError.invalidResponse }
        return Manifest(files: files.sorted { $0.name < $1.name })
    }
}

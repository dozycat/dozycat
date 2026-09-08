import Foundation
import CryptoKit

@main
struct LocalModelTransferTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = URL(string: CommandLine.arguments[1])!
        let data = Data((0..<8193).map { UInt8($0 % 256) })
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        func file(_ path: String) -> LocalModelDownloadSource.File {
            .init(name: "model.safetensors", url: base.appendingPathComponent(path), revision: "test", size: Int64(data.count), sha256: hash)
        }
        let cache = root.appendingPathComponent("resume")
        do {
            _ = try await LocalModelTransfer.download(file("resume"), session: .shared, cacheDirectory: cache, chunkSize: 1024) { _ in }
            fatalError("Server interruption must fail the first attempt")
        } catch LocalModelDownloadSource.DownloadError.invalidResponse {}
        let partial = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil).first!
        let partialData = try Data(contentsOf: partial)
        precondition(partialData.count == 1024)
        let resumed = try await LocalModelTransfer.download(file("resume"), session: .shared, cacheDirectory: cache, chunkSize: 1024) { _ in }
        let resumedData = try Data(contentsOf: resumed)
        precondition(resumedData == data)
        _ = try await LocalModelTransfer.download(file("must-not-request"), session: .shared, cacheDirectory: cache, chunkSize: 1024) { _ in }
        for path in ["full", "wrong-range", "corrupt"] {
            do {
                let result = try await LocalModelTransfer.download(file(path), session: .shared, cacheDirectory: root.appendingPathComponent(path), chunkSize: 1024) { _ in }
                precondition(path == "full")
                let resultData = try Data(contentsOf: result)
                precondition(resultData == data)
            } catch {
                precondition(path != "full")
            }
        }
        print("PASS: interrupted download resumes from byte 1024; verified cache reuse; HTTP 200 fallback; invalid ranges and corrupt content rejected")
    }
}

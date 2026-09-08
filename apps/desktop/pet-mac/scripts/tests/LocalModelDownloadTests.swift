import Foundation

@main
struct LocalModelDownloadTests {
    static func main() async throws {
        var attempts: [LocalModelDownloadSource] = []
        let selected = try await LocalModelDownloadSource.withFallback { source in
            attempts.append(source)
            if source == .huggingFace { throw URLError(.timedOut) }
            return source
        }
        precondition(selected == .modelScope && attempts == [.huggingFace, .modelScope])
        attempts = []
        _ = try await LocalModelDownloadSource.withFallback { source in attempts.append(source); return true }
        precondition(attempts == [.huggingFace])
        attempts = []
        do {
            let _: Bool = try await LocalModelDownloadSource.withFallback { source in
                attempts.append(source); throw CancellationError()
            }
            fatalError("Cancellation swallowed")
        } catch is CancellationError { precondition(attempts == [.huggingFace]) }
        attempts = []
        do {
            let _: Bool = try await LocalModelDownloadSource.withFallback { source in
                attempts.append(source); throw URLError(.cannotConnectToHost)
            }
            fatalError("Failure swallowed")
        } catch { precondition(attempts == [.huggingFace, .modelScope]) }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try Data("abc".utf8).write(to: temp)
        let expected = LocalModelDownloadSource.File(name: "test", url: temp, revision: "test", size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try expected.verify(at: temp)
        try Data("abd".utf8).write(to: temp)
        do { try expected.verify(at: temp); fatalError("Corruption accepted") }
        catch LocalModelDownloadSource.DownloadError.invalidFile {}
        print("PASS: HF priority, fallback, cancellation, double failure, SHA256 corruption rejection")
        if CommandLine.arguments.contains("--live") {
            for size in [4, 2] {
                let id = "mlx-community/Qwen3.5-\(size)B-4bit"
                var manifests: [LocalModelDownloadSource.Manifest] = []
                for source in LocalModelDownloadSource.allCases {
                    let manifest = try await source.manifest(for: id, session: .shared)
                    manifests.append(manifest)
                    let config = manifest.files.first { $0.name == "config.json" }!
                    let (data, response) = try await URLSession.shared.data(from: config.url)
                    try LocalModelDownloadSource.check(response)
                    try data.write(to: temp)
                    try config.verify(at: temp)
                    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                    precondition(json["model_type"] as? String == "qwen3_5")
                    print("PASS: \(source.label) \(id), \(manifest.files.count) files, public download verified")
                }
                let hashes = manifests.map { $0.files.first { $0.name == "model.safetensors" }!.sha256! }
                precondition(hashes[0] == hashes[1], "Sources have different weights")
                print("PASS: \(size)B weight hashes match across sources")
            }
        }
    }
}

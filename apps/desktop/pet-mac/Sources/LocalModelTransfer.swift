import Foundation
import CryptoKit

/// Range transfers retain only complete chunks. Cache identity includes the expected
/// checksum (or source revision for non-LFS files), so resuming cannot mix versions.
enum LocalModelTransfer {
    static func download(_ file: LocalModelDownloadSource.File, session: URLSession,
                         cacheDirectory: URL, chunkSize: Int64 = 32 * 1024 * 1024,
                         progress: @Sendable (Int64) async -> Void) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let identity = file.sha256 ?? "\(file.url.host ?? "")/\(file.revision)/\(file.name)"
        let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let complete = cacheDirectory.appendingPathComponent(key)
        let partial = complete.appendingPathExtension("partial")
        if fm.fileExists(atPath: complete.path) {
            do { try await verify(file, at: complete); await progress(file.size); return complete }
            catch {
                try Task.checkCancellation()
                try fm.removeItem(at: complete)
            }
        }
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        var offset = Int64(try partial.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        if offset > file.size {
            try Data().write(to: partial)
            offset = 0
        }
        await progress(offset)
        while offset < file.size {
            try Task.checkCancellation()
            let last = min(offset + chunkSize, file.size) - 1
            var request = URLRequest(url: file.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("bytes=\(offset)-\(last)", forHTTPHeaderField: "Range")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let (temporary, response) = try await session.download(for: request)
            defer { try? fm.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse else { throw LocalModelDownloadSource.DownloadError.invalidResponse }
            let length = Int64(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            if http.statusCode == 200 {
                // Some providers ignore Range: accept only a complete verified file.
                guard length == file.size else { throw LocalModelDownloadSource.DownloadError.invalidFile }
                try await verify(file, at: temporary)
                try fm.moveItem(at: temporary, to: complete)
                try? fm.removeItem(at: partial)
                await progress(file.size)
                return complete
            }
            guard http.statusCode == 206,
                  http.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(last)/\(file.size)",
                  length == last - offset + 1 else { throw LocalModelDownloadSource.DownloadError.invalidResponse }
            // Only commit a complete verified range to the partial file. If writing fails,
            // truncate to the previous checkpoint rather than retaining a torn range.
            let checkpoint = offset
            do {
                let input = try FileHandle(forReadingFrom: temporary)
                defer { try? input.close() }
                let output = try FileHandle(forWritingTo: partial)
                defer { try? output.close() }
                try output.seekToEnd()
                while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
                    try Task.checkCancellation()
                    try output.write(contentsOf: data)
                }
                try output.synchronize()
            } catch {
                if let output = try? FileHandle(forWritingTo: partial) {
                    try? output.truncate(atOffset: UInt64(checkpoint))
                    try? output.close()
                }
                throw error
            }
            offset += length
            await progress(offset)
        }
        do { try await verify(file, at: partial) }
        catch {
            try Task.checkCancellation()
            try? fm.removeItem(at: partial)
            throw error
        }
        try fm.moveItem(at: partial, to: complete)
        return complete
    }

    private static func verify(_ file: LocalModelDownloadSource.File, at url: URL) async throws {
        let task = Task.detached { try file.verify(at: url) }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

import Foundation

/// 能量流水：core 只存最新值，日历和 K 线要看历史，pet（能量的单落账者）
/// 顺手在 ~/.dozycat/energy/<yyyy-MM>.jsonl 记一本旁账，每行 {"t":ms,"p":生理,"m":心理}。
enum EnergyLog {
    struct Sample {
        let at: Date
        let phys: Double
        let mind: Double
    }

    /// 一根 K 线（能量 0-100 刻度）。up = 收 ≥ 开（回血），用蓝；否则珊瑚。
    struct Candle: Identifiable {
        let id: Int
        let start: Date
        let open: Double
        let close: Double
        let low: Double
        let high: Double
        var up: Bool { close >= open }
        var delta: Double { close - open }
    }

    static var dir: URL {
        if let path = ProcessInfo.processInfo.environment["DOZYCAT_ENERGY_DIR"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return AppPaths.directory("energy")
    }

    static func append(phys: Double, mind: Double, at: Date = Date()) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = "{\"t\":\(Int64(at.timeIntervalSince1970 * 1000)),"
            + "\"p\":\(Int(phys.rounded())),\"m\":\(Int(mind.rounded()))}\n"
        let url = monthFile(at)
        if let handle = FileHandle(forWritingAtPath: url.path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// 最近一次落盘的能量。正式账本暂时被别的进程锁住时，用它接续状态，
    /// 避免重启回退到写死的初始值。按月份倒序找，兼容跨月后的第一次启动。
    static func latestSample() -> Sample? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for file in files
            .filter({ $0.pathExtension == "jsonl" })
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            if let sample = parse(file).last { return sample }
        }
        return nil
    }

    /// 某一天的样本（按时间升序）。
    static func samples(on day: Date) -> [Sample] {
        let calendar = Calendar.current
        return parse(monthFile(day))
            .filter { calendar.isDate($0.at, inSameDayAs: day) }
    }

    /// 某月每天的均值，键是几号（1-31）。没数据的天不在字典里。
    static func dailyAverages(month: Date) -> [Int: (phys: Double, mind: Double)] {
        let calendar = Calendar.current
        var sums: [Int: (p: Double, m: Double, n: Double)] = [:]
        for sample in parse(monthFile(month)) {
            let day = calendar.component(.day, from: sample.at)
            let old = sums[day] ?? (0, 0, 0)
            sums[day] = (old.p + sample.phys, old.m + sample.mind, old.n + 1)
        }
        return sums.mapValues { (phys: $0.p / $0.n, mind: $0.m / $0.n) }
    }

    /// 把一天的样本聚成 `count` 根 K 线（OHLC）。样本太少画不成线时返回空。
    static func candles(from samples: [Sample], count: Int = 10) -> [Candle] {
        guard samples.count >= count,
              let first = samples.first, let last = samples.last,
              last.at > first.at else { return [] }
        let span = last.at.timeIntervalSince(first.at) / Double(count)
        var out: [Candle] = []
        for i in 0..<count {
            let start = first.at.addingTimeInterval(span * Double(i))
            let end = first.at.addingTimeInterval(span * Double(i + 1))
            let bucket = samples.filter { $0.at >= start && ($0.at < end || i == count - 1) }
            guard let open = bucket.first, let close = bucket.last else { continue }
            out.append(Candle(
                id: i, start: start,
                open: open.phys, close: close.phys,
                low: bucket.map(\.phys).min() ?? open.phys,
                high: bucket.map(\.phys).max() ?? open.phys
            ))
        }
        return out
    }

    /// 最近 `days` 天里、某小时段的生理均值（回血推荐用）。
    static func hourlyPhysAverage(hours: Range<Int>, days: Int) -> (average: Double, sampleDays: Int)? {
        let calendar = Calendar.current
        var perDay: [String: (sum: Double, n: Double)] = [:]
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            for sample in samples(on: day)
            where hours.contains(calendar.component(.hour, from: sample.at)) {
                let key = Garden.day(day)
                let old = perDay[key] ?? (0, 0)
                perDay[key] = (old.sum + sample.phys, old.n + 1)
            }
        }
        guard !perDay.isEmpty else { return nil }
        let dayAverages = perDay.values.map { $0.sum / $0.n }
        return (dayAverages.reduce(0, +) / Double(dayAverages.count), dayAverages.count)
    }

    // MARK: 文件

    private static func monthFile(_ date: Date) -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return dir.appendingPathComponent(f.string(from: date) + ".jsonl")
    }

    private static func parse(_ url: URL) -> [Sample] {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return raw.split(separator: "\n").compactMap { line in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let t = obj["t"] as? Double,
                  let p = obj["p"] as? Double,
                  let m = obj["m"] as? Double else { return nil }
            return Sample(at: Date(timeIntervalSince1970: t / 1000), phys: p, mind: m)
        }
        .sorted { $0.at < $1.at }
    }
}

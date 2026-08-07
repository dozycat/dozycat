import SwiftUI

/// 能量 Widgets（设计稿「能量 WIDGETS」）：把能量当成一种可以经营的资产——
/// 日历看长期，K 线看当天，回血清单是你的「加仓」动作，明日计划提前排回血。
struct EnergyPanelView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                EnergyCalendarCard()
                RechargeListCard()
            }
            VStack(spacing: 20) {
                EnergyKLineCard()
                TomorrowPlanCard()
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(DS.bg.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(DS.lineStrong, lineWidth: 1))
    }
}

/// 卡片底：白纸、发丝线、圆角 20（面板内不再叠投影）。
private struct EnergyCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(22)
            .frame(width: 420, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DS.paper))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DS.line, lineWidth: 1))
    }
}

// MARK: - 能量日历 · 每天两滴颜色，深浅就是当天均值

struct EnergyCalendarCard: View {
    @State private var averages: [Int: (phys: Double, mind: Double)] = [:]

    private var calendar: Calendar { Calendar.current }
    private var today: Int { calendar.component(.day, from: Date()) }

    var body: some View {
        EnergyCard {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: monthTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.ink)
                Spacer()
                legend("心理", color: DS.blue)
                legend("生理", color: DS.coral).padding(.leading, 14)
            }
            .padding(.bottom, 16)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                // 整个网格一个 ForEach、字符串 id：表头（英文 T/T、S/S 重名）、
                // 空位和日期格的 id 一旦撞车，SwiftUI 会直接丢格子
                ForEach(gridCells) { cell in
                    switch cell.kind {
                    case .header(let name):
                        Text(verbatim: name)
                            .font(.system(size: 10))
                            .foregroundStyle(DS.faint)
                    case .blank:
                        Color.clear.frame(height: 1)
                    case .day(let day):
                        dayCell(day)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                CatFace(size: 28, outlined: true)
                Text(verbatim: insight)
                    .font(.system(size: 12))
                    .lineSpacing(5)
                    .foregroundStyle(DS.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }
            .padding(.top, 12)
        }
        .onAppear {
            Task {
                averages = await Task.detached(priority: .userInitiated) {
                    EnergyLog.dailyAverages(month: Date())
                }.value
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let isToday = day == today
        let isFuture = day > today
        let value = averages[day]
        return VStack(spacing: 3) {
            Text(verbatim: "\(day)")
                .font(.system(size: 10))
                .foregroundStyle(isToday ? DS.ink : isFuture ? DS.lineStrong : DS.faint)
            HStack(spacing: 2) {
                Circle().fill(DS.blue).frame(width: 7, height: 7)
                    .opacity(value.map { $0.mind / 100 } ?? 0)
                Circle().fill(DS.coral).frame(width: 7, height: 7)
                    .opacity(value.map { $0.phys / 100 } ?? 0)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isToday ? DS.lineSoft : DS.paper))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(isToday ? DS.ink : DS.lineSoft, lineWidth: isToday ? 1.5 : 1))
    }

    private func legend(_ label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundStyle(DS.muted)
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMM")
        return f.string(from: Date())
    }

    private struct GridCell: Identifiable {
        enum Kind {
            case header(String)
            case blank
            case day(Int)
        }

        let id: String
        let kind: Kind
    }

    private var gridCells: [GridCell] {
        weekdayHeaders.enumerated().map { GridCell(id: "h\($0.offset)", kind: .header($0.element)) }
            + (0..<leadingBlanks).map { GridCell(id: "b\($0)", kind: .blank) }
            + (1...daysInMonth).map { GridCell(id: "d\($0)", kind: .day($0)) }
    }

    private var weekdayHeaders: [String] {
        [String(localized: "一"), String(localized: "二"), String(localized: "三"),
         String(localized: "四"), String(localized: "五"), String(localized: "六"),
         String(localized: "日")]
    }

    /// 周一开头的空格数。
    private var leadingBlanks: Int {
        var comps = calendar.dateComponents([.year, .month], from: Date())
        comps.day = 1
        guard let first = calendar.date(from: comps) else { return 0 }
        return (calendar.component(.weekday, from: first) + 5) % 7
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: Date())?.count ?? 30
    }

    /// 从真实数据里找规律：哪一个星期几的生理均值最浅。数据不足就说实话。
    private var insight: String {
        guard averages.count >= 5 else {
            return String(localized: "颜色越深，那天的能量越足。记满一周，我就能看出你的规律了。")
        }
        var byWeekday: [Int: [Double]] = [:]
        for (day, value) in averages {
            var comps = calendar.dateComponents([.year, .month], from: Date())
            comps.day = day
            guard let date = calendar.date(from: comps) else { continue }
            byWeekday[calendar.component(.weekday, from: date), default: []].append(value.phys)
        }
        let eligible = byWeekday.filter { $0.value.count >= 2 }
            .mapValues { $0.reduce(0, +) / Double($0.count) }
        guard let lowest = eligible.min(by: { $0.value < $1.value }),
              eligible.count >= 2 else {
            return String(localized: "颜色越深，那天的能量越足。再记几天就能看出规律了。")
        }
        let name = calendar.weekdaySymbols[lowest.key - 1]
        return String(localized: "最近的\(name)颜色都偏浅。要不要把那天的回血设成固定动作？")
    }
}

// MARK: - 能量 K 线 · 今天的走势，红涨绿跌换成回血/消耗

struct EnergyKLineCard: View {
    @ObservedObject private var feed = SenseFeed.shared
    @State private var samples: [EnergyLog.Sample] = []
    /// 蜡烛与笔记 app 标注都在 reload() 的后台任务里算好——body 里零 IO 零分桶
    @State private var candles: [EnergyLog.Candle] = []
    @State private var noteApps: [(at: Date, app: String)] = []

    private var dayOpen: Int? { samples.first.map { Int($0.phys.rounded()) } }

    var body: some View {
        EnergyCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("生理能量 · 今天")
                        .font(.system(size: 11)).tracking(2.2).foregroundStyle(DS.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(feed.phys)")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(DS.ink)
                        if let open = dayOpen, feed.phys != open {
                            let up = feed.phys > open
                            Text(verbatim: "\(up ? "▴" : "▾") \(abs(feed.phys - open))")
                                .font(.system(size: 13))
                                .foregroundStyle(up ? DS.blue : DS.coral)
                        }
                    }
                }
                Spacer()
                Text("日内")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.faint)
                    .padding(.vertical, 3).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(DS.line, lineWidth: 1))
            }
            .padding(.bottom, 14)

            chart
                .frame(height: 120)

            HStack {
                ForEach(axisLabels, id: \.self) { label in
                    Text(verbatim: label)
                    if label != axisLabels.last { Spacer() }
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(DS.faint)
            .padding(.top, 6)

            movers
                .padding(.top, 12)
                .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }
                .padding(.top, 12)
        }
        .onAppear { reload() }
        .onChange(of: feed.phys) { _, _ in reload() }
    }

    private func reload() {
        Task {
            let loaded = await Task.detached(priority: .userInitiated) {
                () -> ([EnergyLog.Sample], [EnergyLog.Candle], [(at: Date, app: String)]) in
                let samples = EnergyLog.samples(on: Date())
                return (samples, EnergyLog.candles(from: samples), NoteContext.apps(for: Date()))
            }.value
            samples = loaded.0
            candles = loaded.1
            noteApps = loaded.2
        }
    }

    private var chart: some View {
        Canvas { context, size in
            let candles = candles
            // 纵轴贴着当天的实际区间走，窄幅波动也能看出形状
            let low = candles.map(\.low).min() ?? 0
            let high = candles.map(\.high).max() ?? 100
            let floor = max(0, low - 6)
            let ceiling = min(100, max(high + 6, floor + 12))
            func y(_ value: Double) -> CGFloat {
                let t = (value - floor) / (ceiling - floor)
                return size.height - 5 - CGFloat(t) * (size.height - 10)
            }
            for fraction in [0.25, 0.5, 0.75] {
                let level = floor + (ceiling - floor) * fraction
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(level)))
                line.addLine(to: CGPoint(x: size.width, y: y(level)))
                context.stroke(line, with: .color(DS.lineSoft), lineWidth: 1)
            }
            guard !candles.isEmpty else { return }
            let slot = size.width / CGFloat(candles.count)
            for (i, c) in candles.enumerated() {
                let x = slot * (CGFloat(i) + 0.5)
                let color = c.up ? DS.blue : DS.coral
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(c.high)))
                wick.addLine(to: CGPoint(x: x, y: y(c.low)))
                context.stroke(wick, with: .color(color), lineWidth: 1.5)
                let bodyWidth = min(16, slot * 0.55)
                let top = y(max(c.open, c.close))
                let height = max(4, y(min(c.open, c.close)) - top)
                context.fill(
                    Path(roundedRect: CGRect(x: x - bodyWidth / 2, y: top,
                                             width: bodyWidth, height: height),
                         cornerRadius: 3),
                    with: .color(color)
                )
            }
        }
        .overlay {
            if candles.isEmpty {
                Text("今天的数据还不够画 K 线，过一会儿再来看。")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
            }
        }
    }

    private var axisLabels: [String] {
        guard let first = samples.first, let last = samples.last, samples.count > 1 else {
            return [" "]
        }
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        let span = last.at.timeIntervalSince(first.at)
        return (0..<5).map {
            f.string(from: first.at.addingTimeInterval(span * Double($0) / 4))
        }
    }

    /// 今天最大的几段涨跌，用时间笔记里的前台 app 当上下文标注。
    private var movers: some View {
        let apps = noteApps
        let top = candles.filter { abs($0.delta) >= 3 }
            .sorted { abs($0.delta) > abs($1.delta) }
            .prefix(3)
            .sorted { $0.start < $1.start }
        let f = DateFormatter()
        f.dateFormat = "H:mm"

        return VStack(spacing: 0) {
            if top.isEmpty {
                Text(candles.isEmpty ? "回血和消耗的大事记会出现在这里。" : "今天走得挺平，没什么大起大落。")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            ForEach(top) { candle in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: f.string(from: candle.start))
                        .font(.system(size: 11))
                        .foregroundStyle(DS.faint)
                        .frame(width: 36, alignment: .leading)
                    Text(verbatim: moverLabel(candle, apps: apps))
                        .font(.system(size: 13))
                        .foregroundStyle(DS.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(verbatim: candle.delta >= 0
                        ? "+\(Int(candle.delta.rounded()))"
                        : "−\(Int(abs(candle.delta).rounded()))")
                        .font(.system(size: 13))
                        .foregroundStyle(candle.delta >= 0 ? DS.blue : DS.coral)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    if candle.id != top.last?.id { DS.lineSoft.frame(height: 1) }
                }
            }
        }
    }

    private func moverLabel(_ candle: EnergyLog.Candle, apps: [(at: Date, app: String)]) -> String {
        let mid = candle.start.addingTimeInterval(0)
        if let app = NoteContext.app(near: mid, in: apps) {
            return candle.delta >= 0
                ? String(localized: "在 \(app) 的时候回了一波")
                : String(localized: "在 \(app) 的一段，一路消耗")
        }
        return candle.delta >= 0
            ? String(localized: "回了一波血")
            : String(localized: "持续阴跌的一段")
    }
}

/// 时间笔记的 frontmatter（time + app），给 K 线大波动当标注。
private enum NoteContext {
    static func apps(for day: Date) -> [(at: Date, app: String)] {
        let dir = Garden.notes.appendingPathComponent(Garden.day(day))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var out: [(Date, String)] = []
        for file in Garden.listFiles(dir) {
            guard let text = try? String(contentsOf: dir.appendingPathComponent(file),
                                         encoding: .utf8) else { continue }
            var time: Date?
            var app = ""
            for line in text.split(separator: "\n").prefix(10) {
                if line.hasPrefix("time:") {
                    let raw = line.dropFirst(5)
                        .replacingOccurrences(of: "（本地时间）", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    time = f.date(from: raw)
                } else if line.hasPrefix("app:") {
                    app = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                }
            }
            if let time, !app.isEmpty { out.append((time, app)) }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    static func app(near date: Date, in apps: [(at: Date, app: String)]) -> String? {
        apps.min { abs($0.at.timeIntervalSince(date)) < abs($1.at.timeIntervalSince(date)) }
            .flatMap { abs($0.at.timeIntervalSince(date)) <= 30 * 60 ? $0.app : nil }
    }
}

// MARK: - 回血清单 · 你定义什么能给你充电，它学着推荐

enum RechargeKind: String, Codable {
    case phys, mind

    var color: Color { self == .phys ? DS.coral : DS.blue }
    var label: String {
        self == .phys ? String(localized: "生理") : String(localized: "心理")
    }
}

struct RechargeItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var kind: RechargeKind
    var times = 0
    /// 事后 20 分钟量到的真实回血累计（只累计正的）。
    var measuredGain = 0.0
    var measures = 0
    var hour = 18
    var minute = 30

    var averageGain: Int? {
        measures > 0 ? Int((measuredGain / Double(measures)).rounded()) : nil
    }
}

/// 回血清单的账本：~/.dozycat/recharge.json，pet 单写者。
@MainActor
final class RechargeStore: ObservableObject {
    static let shared = RechargeStore()

    struct Recommendation {
        let key: String
        let name: String
        let reason: String
        let kind: RechargeKind
        let hour: Int
        let minute: Int
    }

    @Published private(set) var items: [RechargeItem] = []
    @Published private(set) var recommendation: Recommendation?
    private var dismissed: Set<String> = []

    private var file: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["DOZYCAT_RECHARGE"]
            ?? (NSHomeDirectory() + "/.dozycat/recharge.json"))
    }

    private struct Book: Codable {
        var items: [RechargeItem]
        var dismissed: [String]
    }

    private init() {
        if let data = try? Data(contentsOf: file),
           let book = try? JSONDecoder().decode(Book.self, from: data) {
            items = book.items
            dismissed = Set(book.dismissed)
        } else {
            // 第一次给三个常见的起手式，账都从 0 记
            items = [
                RechargeItem(name: String(localized: "傍晚散步 20 分钟"), kind: .phys,
                             hour: 18, minute: 30),
                RechargeItem(name: String(localized: "给妈妈打电话"), kind: .mind,
                             hour: 20, minute: 30),
                RechargeItem(name: String(localized: "弹 15 分钟琴"), kind: .mind,
                             hour: 21, minute: 0),
            ]
            save()
        }
        refreshRecommendation()
    }

    func add(name: String, kind: RechargeKind, hour: Int = 18, minute: Int = 30) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(RechargeItem(name: trimmed, kind: kind, hour: hour, minute: minute))
        save()
    }

    func remove(_ item: RechargeItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// 「现在做」：计一次数，猫开心一会儿；20 分钟后回来量真实回了多少。
    func markDone(_ item: RechargeItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].times += 1
        save()
        SenseFeed.shared.celebrate()
        PetStore.shared.recordEnergy(phys: Double(SenseFeed.shared.phys),
                                     mind: Double(SenseFeed.shared.mind),
                                     kind: "recharge:\(item.name)")
        let before = item.kind == .phys ? SenseFeed.shared.phys : SenseFeed.shared.mind
        let id = item.id
        let kind = item.kind
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20 * 60 * 1_000_000_000)
            guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
            let after = kind == .phys ? SenseFeed.shared.phys : SenseFeed.shared.mind
            self.items[index].measuredGain += Double(max(0, after - before))
            self.items[index].measures += 1
            self.save()
        }
    }

    func acceptRecommendation() {
        guard let rec = recommendation else { return }
        add(name: rec.name, kind: rec.kind, hour: rec.hour, minute: rec.minute)
        dismissed.insert(rec.key)
        recommendation = nil
        save()
    }

    func dismissRecommendation() {
        guard let rec = recommendation else { return }
        dismissed.insert(rec.key)
        recommendation = nil
        save()
    }

    /// 推荐从真实数据里长出来：最近几天下午的生理能量持续走低才开口。
    func refreshRecommendation() {
        guard recommendation == nil, !dismissed.contains("afternoon-sun"),
              !items.contains(where: { $0.name.contains(String(localized: "太阳")) }),
              let slump = EnergyLog.hourlyPhysAverage(hours: 13..<16, days: 4),
              slump.sampleDays >= 2, slump.average < 55 else { return }
        recommendation = Recommendation(
            key: "afternoon-sun",
            name: String(localized: "午饭后在楼下晒 10 分钟太阳"),
            reason: String(localized: "最近 \(slump.sampleDays) 天下午 1 点到 3 点，生理能量平均只有 \(Int(slump.average.rounded()))，是一天里最低的一段。"),
            kind: .phys, hour: 12, minute: 40
        )
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? (try? encoder.encode(Book(items: items, dismissed: Array(dismissed))))?
            .write(to: file)
    }
}

struct RechargeListCard: View {
    @ObservedObject private var store = RechargeStore.shared
    @State private var adding = false
    @State private var draftName = ""
    @State private var draftKind: RechargeKind = .phys
    @State private var justDid: UUID?

    var body: some View {
        EnergyCard {
            HStack(alignment: .firstTextBaseline) {
                Text("回血清单")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.ink)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { adding.toggle() }
                } label: {
                    Text(adding ? "收起" : "+ 添加")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.coral)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)

            if adding { addRow }

            ForEach(store.items) { item in
                row(item)
            }

            if let rec = store.recommendation {
                recommendationBox(rec)
                    .padding(.top, 14)
            }
        }
    }

    private func row(_ item: RechargeItem) -> some View {
        HStack(spacing: 12) {
            Circle().fill(item.kind.color).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.ink)
                Text(verbatim: statsLine(item))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.muted)
            }
            Spacer()
            Button {
                store.markDone(item)
                justDid = item.id
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if justDid == item.id { justDid = nil }
                }
            } label: {
                Text(justDid == item.id ? "记下了" : "现在做")
                    .font(.system(size: 12))
                    .foregroundStyle(justDid == item.id ? DS.blue : DS.inkSoft)
                    .padding(.vertical, 5).padding(.horizontal, 12)
                    .background(Capsule().stroke(DS.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if item.id != store.items.last?.id { DS.lineSoft.frame(height: 1) }
        }
        .contextMenu {
            Button("从清单里去掉") { store.remove(item) }
        }
    }

    private func statsLine(_ item: RechargeItem) -> String {
        if item.times == 0 {
            return String(localized: "还没做过 · 做一次就开始记账")
        }
        if let gain = item.averageGain, gain > 0 {
            return String(localized: "做过 \(item.times) 次 · 平均回 +\(gain) \(item.kind.label)")
        }
        return String(localized: "做过 \(item.times) 次")
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("比如：楼下走一圈", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(DS.ink)
                .onSubmit(commitAdd)
            ForEach([RechargeKind.phys, .mind], id: \.self) { kind in
                Button {
                    draftKind = kind
                } label: {
                    Text(verbatim: kind.label)
                        .font(.system(size: 11))
                        .foregroundStyle(draftKind == kind ? DS.paper : DS.inkSoft)
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        .background(Capsule().fill(draftKind == kind ? DS.ink : Color.clear))
                        .overlay(Capsule().stroke(draftKind == kind ? Color.clear : DS.lineStrong,
                                                  lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button("好", action: commitAdd)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(DS.coral)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.lineSoft))
        .padding(.bottom, 6)
    }

    private func commitAdd() {
        store.add(name: draftName, kind: draftKind)
        draftName = ""
        withAnimation(.easeOut(duration: 0.15)) { adding = false }
    }

    private func recommendationBox(_ rec: RechargeStore.Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CatFace(size: 24, outlined: true)
                Text("它想给你推荐一个新的")
                    .font(.system(size: 11)).tracking(2.2)
                    .foregroundStyle(DS.muted)
            }
            Text(verbatim: "「\(rec.name)」——\(rec.reason)")
                .font(.system(size: 14))
                .lineSpacing(6)
                .foregroundStyle(DS.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("加到清单") { store.acceptRecommendation() }
                    .buttonStyle(SmallInkPill())
                Button("不了") { store.dismissRecommendation() }
                    .buttonStyle(SmallGhostPill())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: 0xF7F6F3)))
    }
}

// MARK: - 明日排血计划 · 提前把回血排进去

struct TomorrowPlanCard: View {
    @ObservedObject private var feed = SenseFeed.shared
    @ObservedObject private var store = RechargeStore.shared
    @State private var monthAverages: [Int: (phys: Double, mind: Double)] = [:]

    private var calendar: Calendar { Calendar.current }
    private var tomorrow: Date { calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date() }

    var body: some View {
        content
            .onAppear {
                Task {
                    monthAverages = await Task.detached(priority: .userInitiated) {
                        EnergyLog.dailyAverages(month: Date())
                    }.value
                }
            }
    }

    private var content: some View {
        EnergyCard {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.ink)
                Spacer()
                Text(verbatim: subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.faint)
            }
            .padding(.bottom, 8)

            if planItems.isEmpty {
                Text("清单还空着——先在回血清单里添一两个动作，我才好帮你排。")
                    .font(.system(size: 12))
                    .lineSpacing(5)
                    .foregroundStyle(DS.muted)
                    .padding(.vertical, 10)
            }

            ForEach(planItems) { item in
                planRow(item)
            }

            Text(verbatim: forecast)
                .font(.system(size: 12))
                .lineSpacing(6)
                .foregroundStyle(DS.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }
                .padding(.top, 8)
        }
    }

    private var planItems: [RechargeItem] {
        store.items.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    private func planRow(_ item: RechargeItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(format: "%d:%02d", item.hour, item.minute))
                .font(.system(size: 11))
                .foregroundStyle(item.kind.color)
                .frame(width: 40, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "☐ \(item.name)")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.ink)
                Text(verbatim: rowNote(item))
                    .font(.system(size: 11))
                    .foregroundStyle(item.kind.color.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            LinearGradient(colors: [item.kind.color.opacity(0.06), .clear],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottom) {
            if item.id != planItems.last?.id { DS.lineSoft.frame(height: 1) }
        }
    }

    private func rowNote(_ item: RechargeItem) -> String {
        if let gain = item.averageGain, gain > 0 {
            return String(localized: "你的老朋友 · 平均回 +\(gain)")
        }
        return item.times > 0
            ? String(localized: "做过 \(item.times) 次 · 它排的")
            : String(localized: "它排的 · 新习惯")
    }

    private var title: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEE")
        return String(localized: "明天 · \(f.string(from: tomorrow))")
    }

    /// 副标题从日历数据里来：明天这个星期几要是最近的低谷，就提前说一声。
    /// 数据由 loadMonthAverages() 在后台备好，body 里不读盘。
    private var subtitle: String {
        let averages = monthAverages
        guard averages.count >= 5 else { return String(localized: "按你的回血习惯排的") }
        var byWeekday: [Int: [Double]] = [:]
        for (day, value) in averages {
            var comps = calendar.dateComponents([.year, .month], from: Date())
            comps.day = day
            guard let date = calendar.date(from: comps) else { continue }
            byWeekday[calendar.component(.weekday, from: date), default: []].append(value.phys)
        }
        let eligible = byWeekday.filter { $0.value.count >= 2 }
            .mapValues { $0.reduce(0, +) / Double($0.count) }
        let tomorrowWeekday = calendar.component(.weekday, from: tomorrow)
        if eligible.count >= 2,
           eligible.min(by: { $0.value < $1.value })?.key == tomorrowWeekday {
            return String(localized: "预计是个消耗日")
        }
        return String(localized: "按你的回血习惯排的")
    }

    private var forecast: String {
        guard !planItems.isEmpty else {
            return String(localized: "先把今天记满，我明天就能算得更准。")
        }
        // 没量出真实均值的动作先按 +8 估
        let gains = planItems.reduce(0) { $0 + ($1.averageGain ?? 8) }
        let target = min(95, feed.phys + gains)
        guard target > feed.phys else {
            return String(localized: "把清单里的动作做完，明晚大概能稳住今天的水位。")
        }
        return String(localized: "按这个走，明晚收盘生理能量大约 \(target)，比现在多 \(target - feed.phys)。")
    }
}

#Preview {
    EnergyPanelView()
}

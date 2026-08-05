import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                chartSection
                statsRow
                catNote
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(DS.paper)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这一周的你")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DS.ink)
            Text(weekRange)
                .font(.system(size: 13))
                .foregroundStyle(DS.muted)
        }
    }

    private var weekRange: String {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -6, to: now) ?? now
        let style = Date.FormatStyle().month().day()
        return "\(start.formatted(style)) – \(now.formatted(style))"
    }

    // MARK: 能量曲线

    private var chartSection: some View {
        VStack(spacing: 14) {
            HStack {
                Text("能量曲线")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.ink)
                Spacer()
                HStack(spacing: 14) {
                    legend("心理", color: DS.blue)
                    legend("生理", color: DS.coral)
                }
            }
            EnergyChart()
                .frame(height: 100)
            HStack {
                let days = axisLabels
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    Text(day)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.faint)
                    if i < days.count - 1 { Spacer() }
                }
            }
        }
    }

    /// 最近 7 天的坐标轴短标签（最后一位是「今」），跟随当前语言。
    private var axisLabels: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let today = calendar.component(.weekday, from: Date())
        let labels = (0..<6).map { offset -> String in
            symbols[((today - 1) - 6 + offset + 14) % 7]
        }
        return labels + [String(localized: "今")]
    }

    private func legend(_ label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 5) {
            color.frame(width: 10, height: 2)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(DS.muted)
        }
    }

    // MARK: 统计

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(label: "平均睡眠",
                     value: Text("6").font(.system(size: 30, weight: .light))
                        + Text("h ").font(.system(size: 14)).foregroundColor(DS.muted)
                        + Text("41").font(.system(size: 30, weight: .light))
                        + Text("m").font(.system(size: 14)).foregroundColor(DS.muted),
                     note: "比上周少 32 分钟", noteColor: DS.blue)
            Rectangle()
                .fill(DS.line)
                .frame(width: 1)
                .padding(.horizontal, 20)
            statCell(label: "起身休息",
                     value: Text("\(model.restCountToday + 15)").font(.system(size: 30, weight: .light))
                        + Text(" 次").font(.system(size: 14)).foregroundColor(DS.muted),
                     note: "答应我的 \(model.restPromiseCount) 次，差一点点", noteColor: DS.coral)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { DS.line.frame(height: 1) }
        .overlay(alignment: .bottom) { DS.line.frame(height: 1) }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statCell(label: LocalizedStringKey, value: Text, note: LocalizedStringKey,
                          noteColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .tracking(2.2)
                .foregroundStyle(DS.muted)
            value.foregroundColor(DS.ink)
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(noteColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 懒猫的话

    private var catNote: some View {
        HStack(alignment: .top, spacing: 16) {
            CatFace(size: 40, outlined: true)
                .padding(.top, 2)
            Text("这周辛苦啦。我发现你一散步心理能量就会回升，下周想不想把傍晚散步固定下来？就当是，陪我出门。")
                .font(.system(size: 14))
                .lineSpacing(9)
                .foregroundStyle(DS.inkSoft)
        }
    }
}

/// The weekly mind/body energy polylines, from the design's 300×100 viewBox.
struct EnergyChart: View {
    private let mind: [CGPoint] = [
        CGPoint(x: 10, y: 58), CGPoint(x: 55, y: 42), CGPoint(x: 100, y: 66),
        CGPoint(x: 145, y: 74), CGPoint(x: 190, y: 50), CGPoint(x: 235, y: 32),
        CGPoint(x: 280, y: 26),
    ]
    private let phys: [CGPoint] = [
        CGPoint(x: 10, y: 42), CGPoint(x: 55, y: 50), CGPoint(x: 100, y: 58),
        CGPoint(x: 145, y: 66), CGPoint(x: 190, y: 62), CGPoint(x: 235, y: 46),
        CGPoint(x: 280, y: 54),
    ]

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / 300
            let sy = geo.size.height / 100
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 50 * sy))
                    path.addLine(to: CGPoint(x: geo.size.width, y: 50 * sy))
                }
                .stroke(DS.bg, lineWidth: 1)

                line(mind, sx: sx, sy: sy).stroke(
                    DS.blue,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                line(phys, sx: sx, sy: sy).stroke(
                    DS.coral,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                endDot(mind, sx: sx, sy: sy, color: DS.blue)
                endDot(phys, sx: sx, sy: sy, color: DS.coral)
            }
        }
    }

    private func line(_ points: [CGPoint], sx: CGFloat, sy: CGFloat) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: first.x * sx, y: first.y * sy))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * sx, y: point.y * sy))
            }
        }
    }

    private func endDot(_ points: [CGPoint], sx: CGFloat, sy: CGFloat, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .position(x: (points.last?.x ?? 0) * sx, y: (points.last?.y ?? 0) * sy)
    }
}

#Preview {
    RootView()
}

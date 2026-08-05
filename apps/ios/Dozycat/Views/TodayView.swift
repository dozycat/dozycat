import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                energyRow
                    .padding(.top, 32)
                todoList
                    .padding(.top, 6)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(DS.paper)
    }

    // MARK: 猫 + 问候

    private var hero: some View {
        VStack(spacing: 4) {
            CatFace(size: 150, breathing: true)
            Text(model.greeting)
                .font(.system(size: 28, weight: .light))
                .padding(.top, 16)
            Text(model.todayMessage)
                .font(.system(size: 14))
                .foregroundStyle(DS.mutedWarm)
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .padding(.top, 4)
            if model.showsRestActions {
                HStack(spacing: 12) {
                    Button("休息 5 分钟") { model.restPresented = true }
                        .buttonStyle(InkPillStyle())
                    Button("再等我一下") {
                        withAnimation(.easeOut(duration: 0.25)) { model.snooze() }
                    }
                    .buttonStyle(GhostPillStyle())
                }
                .padding(.top, 14)
            }
        }
        .foregroundStyle(DS.ink)
    }

    // MARK: 能量

    private var energyRow: some View {
        HStack(spacing: 0) {
            energyCell("心理能量", value: model.mentalEnergy, kind: .mind)
            Rectangle()
                .fill(DS.line)
                .frame(width: 1)
                .padding(.horizontal, 20)
            energyCell("生理能量", value: model.physicalEnergy, kind: .body)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) { DS.line.frame(height: 1) }
        .overlay(alignment: .bottom) { DS.line.frame(height: 1) }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func energyCell(_ label: LocalizedStringKey, value: Int, kind: EnergyKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .tracking(2.2)
                .foregroundStyle(DS.muted)
            (Text("\(value)").font(.system(size: 34, weight: .light)).foregroundColor(DS.ink)
                + Text(" /100").font(.system(size: 13)).foregroundColor(DS.muted))
            GeometryReader { geo in
                Capsule().fill(DS.bg)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(kind.color)
                            .frame(width: geo.size.width * CGFloat(value) / 100)
                            .animation(.easeOut(duration: 0.6), value: value)
                    }
            }
            .frame(height: 3)
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 今日事项

    private var todoList: some View {
        VStack(spacing: 0) {
            todoRow(dot: DS.blue,
                    text: "喝水 \(model.waterCups)/\(model.waterGoal) 杯",
                    time: model.waterTimeLabel) {
                model.drinkWater()
            }
            rowDivider
            todoRow(dot: DS.coral, text: "傍晚散步 · 今天有晚霞", time: "18:30") {}
            rowDivider
            todoRow(dot: DS.lineStrong, text: "睡前模式 · 今晚早点哦", time: "23:00") {
                model.sleepPresented = true
            }
        }
    }

    private var rowDivider: some View {
        DS.lineSoft.frame(height: 1)
    }

    private func todoRow(dot: Color, text: LocalizedStringKey, time: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(DS.ink)
                Spacer(minLength: 8)
                Text(time)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
            }
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RootView()
}

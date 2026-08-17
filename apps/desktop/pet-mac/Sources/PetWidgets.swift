import SwiftUI

/// 能量胶囊 — 悬停猫猫才出现，数字平时藏起来（设计稿「能量刻度」）。
struct EnergyCapsule: View {
    @ObservedObject private var feed = SenseFeed.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                row(label: "心理能量", value: feed.mind, color: DS.blue, warn: false)
                bar(value: feed.mind, color: DS.blue)
                row(label: "生理能量", value: feed.phys, color: DS.coral, warn: feed.phys < 50)
                bar(value: feed.phys, color: DS.coral)
                Text(tip)
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(DS.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .overlay(alignment: .top) { DS.lineSoft.frame(height: 1) }
            }
            .padding(16)
            .frame(width: 220)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DS.paper)
                .shadow(color: DS.ink.opacity(0.16), radius: 22, y: 16))

            DS.lineStrong.frame(width: 1, height: 14)
        }
    }

    // 这里的账要和能量模型对得上（lib.rs tuning）：离开 3 分钟起算，
    // 前 10 分钟每分钟 +1（短憩红利），一刻钟 ≈ +11。
    private var tip: LocalizedStringKey {
        if feed.phys < 50 { return "久坐掉的。站起来歇一刻钟，能回十来点" }
        if feed.mind < 50 { return "心理有点耗。跟我说说，或者出去走走？" }
        return "状态不错。保持这个节奏就好"
    }

    private func row(label: LocalizedStringKey, value: Int, color: Color, warn: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 11)).tracking(2.2).foregroundStyle(DS.muted)
            Spacer()
            Text("\(value)")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(warn ? color : DS.ink)
        }
    }

    private func bar(value: Int, color: Color) -> some View {
        GeometryReader { geo in
            Capsule().fill(DS.bg)
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 100)) / 100)
                }
        }
        .frame(height: 3)
    }
}

/// 提醒卡 — 右上角滑入，20 秒后自己走（设计稿「提醒」）。
struct ReminderCard: View {
    let message: String
    let countLine: String
    var onGo: () -> Void
    var onSnooze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                CatFace(size: 40, outlined: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: message)
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .foregroundStyle(DS.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: countLine)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.muted)
                }
            }
            HStack(spacing: 10) {
                Button("这就去", action: onGo).buttonStyle(SmallInkPill())
                Button("3 分钟后", action: onSnooze).buttonStyle(SmallGhostPill())
            }
            .padding(.leading, 54)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(width: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DS.paper)
            .shadow(color: DS.ink.opacity(0.16), radius: 25, y: 20))
    }
}

struct SmallInkPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13)).foregroundStyle(DS.paper)
            .padding(.vertical, 8).padding(.horizontal, 18)
            .background(Capsule().fill(DS.ink))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SmallGhostPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13)).foregroundStyle(DS.inkSoft)
            .padding(.vertical, 8).padding(.horizontal, 18)
            .background(Capsule().stroke(DS.lineStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

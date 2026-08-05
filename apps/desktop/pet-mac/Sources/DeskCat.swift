import SwiftUI

/// 桌宠的 8 种状态（「dozycat 桌面套件.dc.html」猫猫状态）。
/// 原则：猫本身就是能量表——身体和表情反映状态，数字只在悬停/菜单栏出现。
enum CatMood {
    case doze      // 打盹 · 默认：一切都好，慢慢呼吸着陪你
    case asleep    // 睡着了：睡前模式，它比你先睡（zz、耳朵塌、头更低）
    case happy     // 开心：拱形眼 + 张嘴 + 大腮红
    case curious   // 好奇：圆眼高光 + 一只耳朵竖起 + 歪头
    case worried   // 担心你：挑眉 + 圆眼 + 抿嘴
    case drained   // 没电了：整只摊平，耳朵垂 24°
    case breathing // 陪你呼吸：慢呼吸 + 蓝光 + O 嘴
    case missYou   // 想你了：歪头 -5° + 眯眼 + 超大腮红
}

/// 桌面猫（110×96 设计空间，可缩放）。几何逐状态对齐设计稿。
struct DeskCat: View {
    var mood: CatMood = .doze
    var size: CGFloat = 110

    @State private var breatheUp = false
    @State private var eyesClosed = false

    private var s: CGFloat { size / 110 }
    private var breathes: Bool { mood != .asleep && mood != .drained }
    private var breatheDuration: Double { mood == .breathing ? 4.8 : 3.4 }

    var body: some View {
        canvas
            .scaleEffect(s, anchor: .topLeading)
            .frame(width: 110 * s, height: 96 * s, alignment: .topLeading)
            .rotationEffect(.degrees(mood == .missYou ? -5 : 0))
            .scaleEffect(breathes && breatheUp ? 1.02 : 1)
            .offset(y: breathes && breatheUp ? -5 * s : 0)
            .onAppear {
                guard breathes else { return }
                withAnimation(.easeInOut(duration: breatheDuration).repeatForever(autoreverses: true)) {
                    breatheUp = true
                }
            }
            .task(id: blinkTaskKey) {
                guard blinks else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_600_000_000)
                    withAnimation(.easeIn(duration: 0.08)) { eyesClosed = true }
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    withAnimation(.easeOut(duration: 0.10)) { eyesClosed = false }
                }
            }
            .accessibilityHidden(true)
    }

    private var blinks: Bool { mood == .doze }
    private var blinkTaskKey: Bool { blinks }

    @ViewBuilder
    private var canvas: some View {
        switch mood {
        case .doze: doze
        case .asleep: asleep
        case .happy: happy
        case .curious: curious
        case .worried: worried
        case .drained: drained
        case .breathing: breathing
        case .missYou: missYou
        }
    }

    // MARK: 部件

    private func ear(left: Bool, x: CGFloat, y: CGFloat, rotate: CGFloat,
                     opacity: Double = 1, shadow: Double = 0.08) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: left ? 22 : 7,
            bottomLeadingRadius: left ? 8 : 14,
            bottomTrailingRadius: left ? 14 : 8,
            topTrailingRadius: left ? 7 : 22,
            style: .continuous
        )
        .fill(.white)
        .shadow(color: DS.ink.opacity(shadow), radius: 6, y: 4)
        .frame(width: 29, height: 27)
        .rotationEffect(.degrees(rotate))
        .opacity(opacity)
        .position(x: x, y: y)
    }

    private func head(top: CGFloat, inset: CGFloat = 4, tilt: CGFloat = 0,
                      glow: Bool = false,
                      @ViewBuilder face: () -> some View) -> some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(LinearGradient(colors: [.white, .white, DS.headShade],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: DS.ink.opacity(0.12), radius: 12, y: 10)
                .shadow(color: glow ? DS.blue.opacity(0.25) : .clear, radius: 20)
            face()
        }
        .frame(width: 110 - inset * 2, height: 96 - top)
        .rotationEffect(.degrees(tilt))
        .position(x: 55, y: top + (96 - top) / 2)
    }

    private func eyeSleepy(x: CGFloat, y: CGFloat) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 5.5,
                               bottomTrailingRadius: 5.5, topTrailingRadius: 2,
                               style: .continuous)
            .fill(DS.ink)
            .frame(width: 11, height: 6)
            .scaleEffect(y: eyesClosed ? 0.2 : 1)
            .position(x: x, y: y)
    }

    private func eyeLine(x: CGFloat, y: CGFloat, w: CGFloat = 12, rotate: CGFloat = 0) -> some View {
        Capsule().fill(DS.ink)
            .frame(width: w, height: 2.5)
            .rotationEffect(.degrees(rotate))
            .position(x: x, y: y)
    }

    private func eyeRound(x: CGFloat, y: CGFloat, d: CGFloat, highlight: Bool = false) -> some View {
        ZStack {
            Circle().fill(DS.ink).frame(width: d, height: d)
            if highlight {
                Circle().fill(.white).frame(width: 3, height: 3).offset(x: -d * 0.2, y: -d * 0.2)
            }
        }
        .position(x: x, y: y)
    }

    /// 拱形眼（开心/想你了）：上半圆弧线
    private func eyeArc(x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .trim(from: 0.5, to: 1.0)
            .stroke(DS.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 12, height: 12)
            .position(x: x, y: y)
    }

    private func nose(x: CGFloat, y: CGFloat) -> some View {
        Ellipse().fill(DS.blush).frame(width: 6, height: 5).position(x: x, y: y)
    }

    private func cheek(x: CGFloat, y: CGFloat, w: CGFloat = 11, h: CGFloat = 6,
                       color: Color = DS.blushSoft) -> some View {
        Ellipse().fill(color).frame(width: w, height: h).position(x: x, y: y)
    }

    // MARK: 8 种状态（坐标 = 设计稿 110×96 空间）

    private var doze: some View {
        ZStack(alignment: .topLeading) {
            ear(left: true, x: 26.5, y: 17.5, rotate: -4)
            ear(left: false, x: 83.5, y: 17.5, rotate: 4)
            head(top: 13) {
                eyeSleepy(x: 28.5, y: 39)
                eyeSleepy(x: 73.5, y: 39)
                nose(x: 51, y: 48.5)
            }
        }
        .frame(width: 110, height: 96, alignment: .topLeading)
    }

    private var asleep: some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: "z").font(.system(size: 13, weight: .light))
                .foregroundStyle(DS.faint).position(x: 104, y: 4)
            Text(verbatim: "z").font(.system(size: 16, weight: .light))
                .foregroundStyle(DS.lineStrong).position(x: 116, y: -8)
            ear(left: true, x: 26.5, y: 23.5, rotate: -8)
            ear(left: false, x: 83.5, y: 23.5, rotate: 8)
            head(top: 22, inset: 2) {
                eyeLine(x: 30, y: 33)
                eyeLine(x: 76, y: 33)
                nose(x: 53, y: 42.5)
            }
        }
        .frame(width: 110, height: 96, alignment: .topLeading)
    }

    private var happy: some View {
        ZStack(alignment: .topLeading) {
            ear(left: true, x: 26.5, y: 15.5, rotate: -8)
            ear(left: false, x: 83.5, y: 15.5, rotate: 8)
            head(top: 13) {
                eyeArc(x: 29.5, y: 39)
                eyeArc(x: 72.5, y: 39)
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 9,
                                       bottomTrailingRadius: 9, topTrailingRadius: 0)
                    .fill(DS.ink).frame(width: 9, height: 6).position(x: 51, y: 49)
                cheek(x: 19.5, y: 45)
                cheek(x: 82.5, y: 45)
            }
        }
        .frame(width: 110, height: 96, alignment: .topLeading)
    }

    private var curious: some View {
        ZStack(alignment: .topLeading) {
            ear(left: true, x: 24.5, y: 13.5, rotate: -16)
            ear(left: false, x: 83.5, y: 17.5, rotate: 4)
            head(top: 13, tilt: 3) {
                eyeRound(x: 29, y: 39, d: 10, highlight: true)
                eyeRound(x: 73, y: 39, d: 10, highlight: true)
                nose(x: 51, y: 50.5)
            }
        }
        .frame(width: 110, height: 96, alignment: .topLeading)
    }

    private var worried: some View {
        ZStack(alignment: .topLeading) {
            ear(left: true, x: 26.5, y: 19.5, rotate: -2)
            ear(left: false, x: 83.5, y: 19.5, rotate: 2)
            head(top: 15) {
                eyeLine(x: 28.5, y: 29, w: 11, rotate: 14)
                eyeLine(x: 73.5, y: 29, w: 11, rotate: -14)
                eyeRound(x: 28.5, y: 39.5, d: 9)
                eyeRound(x: 73.5, y: 39.5, d: 9)
                eyeLine(x: 51, y: 51, w: 10)
            }
        }
        .frame(width: 110, height: 96, alignment: .topLeading)
    }

    private var drained: some View {
        ZStack(alignment: .topLeading) {
            ear(left: true, x: 24.5, y: 29.5, rotate: -24, opacity: 0.9, shadow: 0.06)
            ear(left: false, x: 85.5, y: 29.5, rotate: 24, opacity: 0.9, shadow: 0.06)
            // 摊平的头：更宽更矮
            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(LinearGradient(colors: [.white, Color(hex: 0xECEBE7)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: DS.ink.opacity(0.10), radius: 10, y: 8)
                eyeSleepyStatic(x: 32, y: 28)
                eyeSleepyStatic(x: 78, y: 28)
                eyeLine(x: 55, y: 37, w: 8, rotate: -6)
            }
            .frame(width: 110, height: 66)
            .position(x: 55, y: 63)
        }
        .frame(width: 110, height: 96, alignment: .topLeading)
    }

    private func eyeSleepyStatic(x: CGFloat, y: CGFloat) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 6,
                               bottomTrailingRadius: 6, topTrailingRadius: 0)
            .fill(DS.ink).frame(width: 12, height: 4).position(x: x, y: y)
    }

    private var breathing: some View {
        ZStack(alignment: .topLeading) {
            ear(left: true, x: 26.5, y: 17.5, rotate: -4)
            ear(left: false, x: 83.5, y: 17.5, rotate: 4)
            head(top: 13, glow: true) {
                eyeLine(x: 30, y: 35.5)
                eyeLine(x: 76, y: 35.5)
                Circle().stroke(DS.ink, lineWidth: 2.5)
                    .frame(width: 9, height: 9).position(x: 51, y: 48.5)
            }
        }
        .frame(width: 110, height: 96, alignment: .topLeading)
    }

    private var missYou: some View {
        ZStack(alignment: .topLeading) {
            ear(left: true, x: 26.5, y: 17.5, rotate: -10)
            ear(left: false, x: 83.5, y: 17.5, rotate: 10)
            head(top: 13) {
                eyeArc(x: 29.5, y: 39)
                eyeArc(x: 72.5, y: 39)
                nose(x: 51, y: 48.5)
                cheek(x: 20.5, y: 45.5, w: 13, h: 7, color: Color(hex: 0xFFC9BE))
                cheek(x: 81.5, y: 45.5, w: 13, h: 7, color: Color(hex: 0xFFC9BE))
            }
        }
        .frame(width: 110, height: 96, alignment: .topLeading)
    }
}

#Preview("moods") {
    let moods: [(CatMood, String)] = [
        (.doze, "打盹"), (.asleep, "睡着了"), (.happy, "开心"), (.curious, "好奇"),
        (.worried, "担心你"), (.drained, "没电了"), (.breathing, "陪你呼吸"), (.missYou, "想你了"),
    ]
    return LazyVGrid(columns: [GridItem(), GridItem(), GridItem(), GridItem()], spacing: 24) {
        ForEach(moods, id: \.1) { mood, name in
            VStack(spacing: 10) {
                DeskCat(mood: mood)
                Text(verbatim: name).font(.system(size: 12))
            }
        }
    }
    .padding(40)
    .background(DS.paper)
}

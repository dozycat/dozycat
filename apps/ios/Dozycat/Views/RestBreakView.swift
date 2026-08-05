import SwiftUI

/// 休息时刻 — the screen dims and the cat asks you to step away
/// (design screen 08, adapted for mobile).
struct RestBreakView: View {
    @EnvironmentObject private var model: AppModel
    @State private var remaining = 5 * 60
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            DS.night.ignoresSafeArea()

            VStack(spacing: 12) {
                CatFace(size: 130, breathing: true)
                Text("该歇一会儿了")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(DS.ink)
                    .padding(.top, 10)
                Text(timeLabel)
                    .font(.system(size: 44, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(DS.coral)
                Text("手头的事我帮你原样留着，\n去伸个懒腰、看看窗外。")
                    .font(.system(size: 14))
                    .lineSpacing(9)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.inkSoft)
                Button("提前回来") { model.finishRest(early: true) }
                    .buttonStyle(GhostPillStyle())
                    .padding(.top, 12)
                Text("今天第 \(model.restCountToday + 1) 次休息 · 你答应过自己的")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.faint)
                    .padding(.top, 4)
            }
            .padding(.vertical, 44)
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(DS.paper))
            .padding(.horizontal, 24)
        }
        .onReceive(timer) { _ in
            if remaining > 1 {
                remaining -= 1
            } else {
                model.finishRest(early: false)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var timeLabel: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}

#Preview {
    RestBreakView().environmentObject(AppModel())
}

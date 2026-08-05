import SwiftUI

/// 睡前模式 — the day winds down (design screen 05).
struct SleepView: View {
    @EnvironmentObject private var model: AppModel
    @State private var breathing = false
    @State private var rain = false

    var body: some View {
        ZStack {
            DS.night.ignoresSafeArea()

            VStack(spacing: 28) {
                hero
                recap
                tools
                Spacer(minLength: 0)
                footer
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            CatFace(size: 130, asleep: true, breathing: true)
                .shadow(color: .white.opacity(0.15), radius: 30)
            Text("今天也辛苦了")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DS.nightInk)
                .padding(.top, 18)
            Text(subline)
                .font(.system(size: 13))
                .foregroundStyle(DS.nightMuted)
        }
    }

    private var subline: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: Date())
        return String(localized: "\(time) · 心理能量 \(model.mentalEnergy) · 生理能量 \(model.physicalEnergy)")
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("今天你做到的三件小事")
                .font(.system(size: 11))
                .tracking(3.3)
                .foregroundStyle(DS.nightMuted)
                .padding(.bottom, 8)
            recapRow("01", "鼓起勇气见了小林，还聊开了")
            recapRow("02", "难过的时候没有硬扛，出门走了一圈")
            recapRow("03", "喝够了 8 杯水，第一次")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recapRow(_ index: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(index)
                .font(.system(size: 12))
                .foregroundStyle(DS.nightMuted)
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(6)
                .foregroundStyle(DS.nightInk)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { DS.nightInk.opacity(0.1).frame(height: 1) }
    }

    private var tools: some View {
        HStack(spacing: 12) {
            toolButton(breathing ? "跟着我……吸气，呼气" : "跟着我呼吸 3 分钟", active: breathing) {
                breathing.toggle()
                if breathing { rain = false }
            }
            toolButton(rain ? "雨声淅淅沥沥…" : "听点雨声", active: rain) {
                rain.toggle()
                if rain { breathing = false }
            }
        }
    }

    private func toolButton(_ label: LocalizedStringKey, active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(DS.nightInk)
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(active ? DS.coral.opacity(0.7) : DS.nightInk.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 16) {
            Text("明早 7:30 我轻轻叫你")
                .font(.system(size: 12))
                .foregroundStyle(DS.nightMuted)
            Button("晚安，懒猫") { model.sleepPresented = false }
                .buttonStyle(PaperPillStyle())
        }
    }
}

#Preview {
    SleepView().environmentObject(AppModel())
}

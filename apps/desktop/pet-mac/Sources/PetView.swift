import SwiftUI

/// 桌宠本体：气泡 + 会呼吸眨眼的猫（设计稿 07，与 iOS 同一只 CatFace）。
struct PetView: View {
    @ObservedObject private var feed = SenseFeed.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 14) {
            Spacer(minLength: 0)
            if let bubble = feed.bubble {
                Text(bubble)
                    .font(.system(size: 13))
                    .lineSpacing(6)
                    .foregroundStyle(DS.ink)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 18)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 16, bottomLeadingRadius: 16,
                            bottomTrailingRadius: 4, topTrailingRadius: 16,
                            style: .continuous
                        )
                        .fill(.white)
                        .shadow(color: DS.ink.opacity(0.12), radius: 15, y: 10)
                    )
                    .frame(maxWidth: 250, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            CatFace(size: 130, breathing: true)
                .padding(.trailing, 24)
        }
        .padding(20)
        .frame(width: 300, height: 340, alignment: .bottomTrailing)
        .animation(.easeOut(duration: 0.3), value: feed.bubble)
    }
}

#Preview {
    PetView()
}

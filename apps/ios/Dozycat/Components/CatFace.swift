import SwiftUI

/// The dozycat mascot, drawn in shapes — ears, head, eyes, nose, cheeks.
/// Geometry lives in a fixed 150×132 space (matching the design's CSS cat)
/// and is scaled to `size`.
struct CatFace: View {
    var size: CGFloat = 150
    var asleep = false
    /// Small line-drawn avatar variant (chat header, review note).
    var outlined = false
    var breathing = false

    @State private var breatheUp = false
    @State private var eyesClosed = false

    private var s: CGFloat { size / 150 }

    var body: some View {
        canvas
            .scaleEffect(s, anchor: .topLeading)
            .frame(width: 150 * s, height: 132 * s, alignment: .topLeading)
            .scaleEffect(breathing && breatheUp ? 1.02 : 1)
            .offset(y: breathing && breatheUp ? -5 * s : 0)
            .onAppear {
                guard breathing else { return }
                withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                    breatheUp = true
                }
            }
            .task {
                guard !asleep && !outlined else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_600_000_000)
                    withAnimation(.easeIn(duration: 0.08)) { eyesClosed = true }
                    try? await Task.sleep(nanoseconds: 140_000_000)
                    withAnimation(.easeOut(duration: 0.10)) { eyesClosed = false }
                }
            }
            .accessibilityHidden(true)
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            ear(left: true)
            ear(left: false)
            head
            if asleep {
                closedEye.position(x: 50.5, y: 74)
                closedEye.position(x: 99.5, y: 74)
            } else {
                openEye.position(x: 50.5, y: 74.5)
                openEye.position(x: 99.5, y: 74.5)
            }
            if !outlined && !asleep {
                Ellipse().fill(DS.blush)
                    .frame(width: 8, height: 6)
                    .position(x: 75, y: 87)
                Ellipse().fill(DS.blushSoft).opacity(0.8)
                    .frame(width: 10, height: 5)
                    .position(x: 32, y: 80.5)
                Ellipse().fill(DS.blushSoft).opacity(0.8)
                    .frame(width: 10, height: 5)
                    .position(x: 118, y: 80.5)
            }
        }
        .frame(width: 150, height: 132, alignment: .topLeading)
    }

    private func ear(left: Bool) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: left ? 30 : 10,
            bottomLeadingRadius: left ? 12 : 19,
            bottomTrailingRadius: left ? 19 : 12,
            topTrailingRadius: left ? 10 : 30,
            style: .continuous
        )
        return ZStack {
            if outlined {
                shape.fill(.white)
                shape.stroke(DS.catLine, lineWidth: 2)
            } else {
                shape.fill(.white)
                    .shadow(color: DS.catInk.opacity(0.08), radius: 9, y: 6)
            }
        }
        .frame(width: 40, height: 38)
        .rotationEffect(.degrees(left ? -4 : 4))
        .position(x: left ? 36 : 114, y: 25)
    }

    private var head: some View {
        ZStack {
            if outlined {
                Ellipse().fill(.white)
                Ellipse().stroke(DS.catLine, lineWidth: 2)
            } else {
                Ellipse()
                    .fill(LinearGradient(
                        colors: [.white, .white, DS.headShade],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .shadow(color: DS.catInk.opacity(0.10), radius: 15, y: 14)
            }
        }
        .frame(width: 140, height: 114)
        .position(x: 75, y: 75)
    }

    private var openEye: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 2, bottomLeadingRadius: 7.5,
            bottomTrailingRadius: 7.5, topTrailingRadius: 2,
            style: .continuous
        )
        .fill(DS.catInk)
        .frame(width: 15, height: 9)
        .scaleEffect(y: eyesClosed ? 0.15 : 1, anchor: .center)
    }

    private var closedEye: some View {
        Capsule().fill(DS.night).frame(width: 14, height: 2.5)
    }
}

#Preview("cat") {
    VStack(spacing: 40) {
        CatFace(size: 150, breathing: true)
        CatFace(size: 130, asleep: true)
        CatFace(size: 44, outlined: true)
    }
    .padding(60)
    .background(DS.paper)
}

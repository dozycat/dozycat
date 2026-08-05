import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Design tokens from `dozycat v2.dc.html` (Claude Design).
enum DS {
    // Surfaces
    static let paper = Color(hex: 0xFAFAF8)      // app background
    static let bg = Color(hex: 0xEDECE8)         // page / bar track
    static let night = Color(hex: 0x232326)      // sleep mode background

    // Ink
    static let ink = Color(hex: 0x2E2E33)
    static let inkSoft = Color(hex: 0x6E6C66)
    static let mutedWarm = Color(hex: 0x8B8880)
    static let muted = Color(hex: 0xA6A39B)
    static let faint = Color(hex: 0xB9B6AE)
    static let nightMuted = Color(hex: 0x8B8B93)
    static let nightInk = Color(hex: 0xEDECE8)

    // Lines
    static let line = Color(hex: 0xE8E6E0)
    static let lineSoft = Color(hex: 0xF0EEE9)
    static let lineStrong = Color(hex: 0xDEDCD5)

    // Accents — 生理 coral / 心理 blue
    static let coral = Color(hex: 0xFF8A75)
    static let coralDeep = Color(hex: 0xE86F5A)
    static let blush = Color(hex: 0xFFB3A6)
    static let blushSoft = Color(hex: 0xFFD9D1)
    static let blue = Color(hex: 0x7C8DB5)

    static let headShade = Color(hex: 0xF4F3EF)  // bottom of the cat's head gradient
}

// MARK: - Shared button styles

struct InkPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(DS.paper)
            .padding(.vertical, 11)
            .padding(.horizontal, 24)
            .background(Capsule().fill(DS.ink))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct GhostPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(DS.inkSoft)
            .padding(.vertical, 11)
            .padding(.horizontal, 24)
            .background(Capsule().stroke(DS.lineStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct PaperPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(DS.night)
            .padding(.vertical, 15)
            .padding(.horizontal, 48)
            .background(Capsule().fill(DS.paper))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

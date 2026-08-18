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

    /// 亮/暗双值动态色。macOS 面板要跟系统外观走（vibrancy 底下亮色纸面会刺眼）；
    /// iOS 端暂时锁亮色（界面围绕纸面设计，暗色适配另起炉灶时再放开）。
    init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
        #else
        self.init(hex: light)
        #endif
    }
}

/// Design tokens from `dozycat v2.dc.html` (Claude Design)。
/// 中性色带暗色档（夜里纸面变墨面，字反白），品牌色与猫的固有色不随外观变。
enum DS {
    // Surfaces
    static let paper = Color(light: 0xFAFAF8, dark: 0x26262A)  // app background
    static let bg = Color(light: 0xEDECE8, dark: 0x1E1E21)     // page / bar track
    static let card = Color(light: 0xFFFFFF, dark: 0x303035)   // 抬高一层的卡片面
    static let night = Color(hex: 0x232326)                    // sleep mode background

    // Ink
    static let ink = Color(light: 0x2E2E33, dark: 0xEDECE8)
    static let inkSoft = Color(light: 0x6E6C66, dark: 0xA7A6AD)
    static let mutedWarm = Color(light: 0x8B8880, dark: 0x84838B)
    static let muted = Color(light: 0xA6A39B, dark: 0x8B8B93)
    static let faint = Color(light: 0xB9B6AE, dark: 0x5E5E66)
    static let nightMuted = Color(hex: 0x8B8B93)
    static let nightInk = Color(hex: 0xEDECE8)

    // Lines
    static let line = Color(light: 0xE8E6E0, dark: 0x3A3A40)
    static let lineSoft = Color(light: 0xF0EEE9, dark: 0x313136)
    static let lineStrong = Color(light: 0xDEDCD5, dark: 0x44444B)

    // Accents — 生理 coral / 心理 blue（两种外观通用）
    static let coral = Color(hex: 0xFF8A75)
    static let coralDeep = Color(hex: 0xE86F5A)
    static let blush = Color(hex: 0xFFB3A6)
    static let blushSoft = Color(hex: 0xFFD9D1)
    static let blue = Color(light: 0x7C8DB5, dark: 0x93A3C8)

    // 猫的固有色：脸永远是白的，五官和描边不随外观反色
    static let headShade = Color(hex: 0xF4F3EF)  // bottom of the cat's head gradient
    static let catInk = Color(hex: 0x2E2E33)     // 五官 / 投影基色
    static let catLine = Color(hex: 0xE8E6E0)    // 轮廓描边
}

#if os(macOS)
/// 桌面常驻小件的共同外观。
///
/// 能量卡是这类组件的视觉基准：实色纸面、无外描边、柔和阴影。独立窗口
/// 会在内容外留透明缓冲承接同一份 SwiftUI 阴影，避免 NSPanel 系统阴影带出
/// 一圈硬边。
enum DesktopCardChrome {
    static let cornerRadius: CGFloat = 16
    static let divider = DS.lineSoft
    static let controlStroke = DS.line
    static let shadowColor = DS.ink.opacity(0.16)
    static let shadowRadius: CGFloat = 22
    static let shadowY: CGFloat = 16
    /// 22pt 模糊核加 16pt 下偏移在 40pt 处仍有可见 alpha；留到约 3.5σ
    /// 之外，让透明窗边界处的阴影真正衰减到肉眼不可见，避免矩形截断线。
    static let windowShadowPadding: CGFloat = 96

    static func shape(radius: CGFloat = cornerRadius) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    static func surface(radius: CGFloat = cornerRadius,
                        elevated: Bool = true) -> some View {
        shape(radius: radius)
            .fill(DS.paper)
            .shadow(
                color: elevated ? shadowColor : .clear,
                radius: elevated ? shadowRadius : 0,
                y: elevated ? shadowY : 0
            )
    }
}
#endif

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

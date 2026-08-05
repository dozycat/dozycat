import SwiftUI

@main
struct DozycatPetApp: App {
    @NSApplicationDelegateAdaptor(PetAppDelegate.self) private var delegate
    @ObservedObject private var feed = SenseFeed.shared

    var body: some Scene {
        MenuBarExtra {
            Text("心理 \(feed.mind) · 生理 \(feed.phys)")
            Divider()
            Button("退出懒猫") { NSApp.terminate(nil) }
        } label: {
            Text("懒猫 \(feed.phys)")
        }
    }
}

/// 透明、置顶、可拖动的桌宠窗口（设计稿 07「桌面常驻」）。
final class PetAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let hosting = NSHostingView(rootView: PetView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 340),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.maxX - 340, y: frame.minY + 48))
        }
        window.orderFrontRegardless()
        self.window = window

        SenseFeed.shared.start()
    }
}

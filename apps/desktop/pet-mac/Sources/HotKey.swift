import Carbon.HIToolbox
import AppKit
import SwiftUI

/// 全局快捷键（Carbon RegisterEventHotKey，无需辅助功能权限）。
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private static var handlerInstalled = false
    private static var callbacks: [UInt32: () -> Void] = [:]
    private static var nextId: UInt32 = 1

    @discardableResult
    init(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        let id = Self.nextId
        Self.nextId += 1
        Self.callbacks[id] = callback
        let hotKeyID = EventHotKeyID(signature: OSType(0x445A_4341), id: id) // 'DZCA'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async {
                HotKey.callbacks[hotKeyID.id]?()
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}

/// 无边框浮动面板：Search Everything 的宿主。
final class FloatingPanel<Content: View>: NSPanel {
    init(content: Content, width: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // 阴影交给窗口系统绘制。SwiftUI shadow 不参与 fittingSize，会在透明
        // NSPanel 的矩形边界被裁成直角残片（尤其明显在 Chat 左下角）。
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        let hosting = NSHostingView(rootView: content)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        hosting.setFrameSize(hosting.fittingSize)
        contentView = hosting
        setContentSize(hosting.fittingSize)
    }

    override var canBecomeKey: Bool { true }

    func showCentered(yRatio: CGFloat = 0.62) {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            let size = contentView?.fittingSize ?? frame.size
            setContentSize(size)
            setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                   y: f.minY + f.height * yRatio - size.height / 2))
        }
        makeKeyAndOrderFront(nil)
        invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 挨着桌宠窗弹出（对话面板）；找不到锚点就居中。
    func show(near anchor: NSWindow?) {
        guard let anchor, let screen = anchor.screen ?? NSScreen.main else {
            showCentered(yRatio: 0.4)
            return
        }
        let size = contentView?.fittingSize ?? frame.size
        setContentSize(size)
        let f = screen.visibleFrame
        var origin = NSPoint(x: anchor.frame.maxX - size.width - 20,
                             y: anchor.frame.minY + 200)
        origin.x = max(f.minX + 16, min(origin.x, f.maxX - size.width - 16))
        origin.y = max(f.minY + 16, min(origin.y, f.maxY - size.height - 16))
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
    }

}

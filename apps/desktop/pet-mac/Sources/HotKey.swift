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

/// 无边框浮动面板：Search Everything / 对话 widget 的宿主。
final class FloatingPanel<Content: View>: NSPanel {
    init(content: Content, width: CGFloat) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // 阴影由 SwiftUI 卡片自带
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        let hosting = NSHostingView(rootView: content)
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
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAbove(window: NSWindow?, offset: NSPoint) {
        guard let anchor = window else { return showCentered() }
        let size = contentView?.fittingSize ?? frame.size
        setContentSize(size)
        setFrameOrigin(NSPoint(x: anchor.frame.maxX - size.width + offset.x,
                               y: anchor.frame.maxY + offset.y))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

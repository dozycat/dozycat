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


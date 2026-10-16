import Carbon
import Foundation
import NoTypeCore

@MainActor final class GlobalHotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let identifier: UInt32
    private static var nextIdentifier: UInt32 = 0
    var registered: Bool { ref != nil }
    init(shortcut: RecordingShortcut = .standard, action: @escaping () -> Void) {
        self.action = action
        Self.nextIdentifier &+= 1
        identifier = Self.nextIdentifier
        guard shortcut.validationError == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue()
                guard id.signature == OSType(0x4E545950), id.id == hotkey.identifier else { return OSStatus(eventNotHandledErr) }
                hotkey.action()
                return noErr
            }
        }, 1, &type, pointer, &handler)
        guard status == noErr else { return }
        let id = EventHotKeyID(signature: OSType(0x4E545950), id: identifier)
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
    deinit { if let ref { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) } }
}

import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon hot keys need no permission.
public final class GlobalHotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    /// `keyCode` is a virtual key code such as `kVK_ANSI_B`. `modifiers` is
    /// a Carbon modifier mask such as `cmdKey | optionKey`.
    public init?(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        Self.installEventHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x4242_4152), id: id) // "BBAR"
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef
        )
        guard status == noErr else { return nil }
        Self.handlers[id] = handler
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        Self.handlers[id] = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            MainActor.assumeIsolated { GlobalHotKey.handlers[hotKeyID.id]?() }
            return noErr
        }, 1, &eventType, nil, nil)
    }
}

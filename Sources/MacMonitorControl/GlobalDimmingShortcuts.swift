import Carbon

@MainActor
final class GlobalDimmingShortcuts {
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    private let action: @MainActor (Double) -> Void

    init(action: @escaping @MainActor (Double) -> Void) {
        self.action = action
    }

    func register() -> Bool {
        guard handler == nil else { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                guard status == noErr, id.signature == 0x4D4D4354 else { return OSStatus(eventNotHandledErr) }
                let receiver = Unmanaged<GlobalDimmingShortcuts>.fromOpaque(context).takeUnretainedValue()
                let amount = id.id == 1 ? 0.1 : -0.1
                Task { @MainActor in receiver.action(amount) }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard installed == noErr else { return false }

        for (index, code) in [kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket].enumerated() {
            let id = EventHotKeyID(signature: 0x4D4D4354, id: UInt32(index + 1))
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey), id,
                                             GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else {
                unregister()
                return false
            }
            keys.append(reference)
        }
        return true
    }

    func unregister() {
        for key in keys { UnregisterEventHotKey(key) }
        keys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

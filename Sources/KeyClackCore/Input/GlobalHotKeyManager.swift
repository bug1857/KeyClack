import Foundation
import Carbon

/// Registers a system-wide global hotkey via Carbon RegisterEventHotKey
/// so the user can toggle KeyClack mute from any focused application.
final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeySignature: OSType = 0x4B43_4C4B // 'KCLK'
    private let hotKeyIdentifier: UInt32 = 1

    var onTrigger: (() -> Void)?

    init() {
        installHandler()
    }

    deinit {
        unregister()
        if let handler = eventHandlerRef {
            _ = RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    func register(preset: HotKeyPreset) {
        unregister()
        guard preset != .disabled else { return }

        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyIdentifier)
        _ = RegisterEventHotKey(
            preset.keyCode,
            preset.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            _ = UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var pressedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressedID
            )
            if status == noErr,
               pressedID.signature == manager.hotKeySignature,
               pressedID.id == manager.hotKeyIdentifier {
                DispatchQueue.main.async {
                    manager.onTrigger?()
                }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }

        _ = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
    }
}

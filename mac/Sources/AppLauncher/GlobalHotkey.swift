#if canImport(AppKit)
import Carbon.HIToolbox
import Foundation
import LauncherCore

/// System-wide hotkey through Carbon's `RegisterEventHotKey`. Unlike an event tap it needs no Accessibility
/// permission and fires even while another app owns the keyboard, but it cannot tell left from right
/// modifier keys; `EventTapHotkey` covers those.
final class GlobalHotkey {
    struct RegistrationError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Distinguishes this registration from the others: every handler installed on the application target
    /// sees every hot-key event, so each instance fires only for its own id.
    private let hotKeyID: EventHotKeyID

    private static var nextID: UInt32 = 1

    init(spec: HotkeySpec) throws {
        guard let keyCode = spec.carbonKeyCode else {
            throw RegistrationError(message: "알 수 없는 키 이름: \(spec.key)")
        }

        hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.nextID)
        Self.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()

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
                guard status == noErr,
                      pressedID.signature == hotkey.hotKeyID.signature,
                      pressedID.id == hotkey.hotKeyID.id else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async { hotkey.onPressed?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else {
            throw RegistrationError(message: "InstallEventHandler failed (\(installStatus))")
        }

        let registerStatus = RegisterEventHotKey(keyCode, spec.modifiers.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.handlerRef = nil
            }
            throw RegistrationError(message: "RegisterEventHotKey failed (\(registerStatus))")
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    /// 'ALMC' as a four-character code.
    private static let signature: OSType = {
        var code: OSType = 0
        for scalar in "ALMC".unicodeScalars {
            code = (code << 8) | OSType(scalar.value & 0xFF)
        }
        return code
    }()
}
#endif

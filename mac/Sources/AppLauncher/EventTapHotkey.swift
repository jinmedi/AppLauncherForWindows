#if canImport(AppKit)
import ApplicationServices
import CoreGraphics
import Foundation
import LauncherCore

/// System-wide hotkey through a CGEvent tap. Needed for chords Carbon cannot express, such as
/// "right Option + Return": the tap sees the NX_DEVICE* bits that say which Option key is down, and
/// swallows the matching key-down so the frontmost app never receives the Return.
/// Requires the Accessibility permission (System Settings > Privacy & Security > Accessibility).
final class EventTapHotkey {
    struct RegistrationError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    var onPressed: (() -> Void)?

    private let spec: HotkeySpec
    private let keyCodes: Set<Int64>
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// True when this process may create keyboard event taps. Pass `prompt: true` to have macOS show its
    /// "would like to control this computer" dialog when the permission is missing.
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    init(spec: HotkeySpec) throws {
        let codes = spec.eventKeyCodes
        guard !codes.isEmpty else {
            throw RegistrationError(message: "알 수 없는 키 이름: \(spec.key)")
        }
        self.spec = spec
        keyCodes = Set(codes.map { Int64($0) })

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let hotkey = Unmanaged<EventTapHotkey>.fromOpaque(userInfo).takeUnretainedValue()
                return hotkey.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw RegistrationError(message: "키보드 이벤트 탭을 만들 수 없습니다. 손쉬운 사용 권한이 필요합니다.")
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that is slow to answer; turn it back on and let the event through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown,
              keyCodes.contains(event.getIntegerValueField(.keyboardEventKeycode)),
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              spec.matches(eventFlags: event.flags.rawValue) else {
            return Unmanaged.passUnretained(event)
        }

        let onPressed = self.onPressed
        DispatchQueue.main.async { onPressed?() }
        return nil // swallowed
    }
}
#endif

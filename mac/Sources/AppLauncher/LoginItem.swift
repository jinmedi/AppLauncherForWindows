#if canImport(AppKit)
import Foundation
import ServiceManagement

/// Registers the app as a login item when `StartAtLogin` is on. Only possible from a real .app bundle;
/// `swift run` has none. Turning the setting off does nothing so a login item added by hand in
/// System Settings is left alone.
enum LoginItem {
    static func apply(startAtLogin: Bool) {
        guard startAtLogin, Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else {
            return
        }

        let service = SMAppService.mainApp
        guard service.status != .enabled else {
            return
        }

        do {
            try service.register()
        } catch {
            NSLog("[AppLauncher] could not register login item: %@", String(describing: error))
        }
    }
}
#endif

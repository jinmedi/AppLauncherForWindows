#if canImport(AppKit)
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu-bar only: no Dock icon, no main menu. Info.plist sets LSUIElement too for the bundled build.
app.setActivationPolicy(.accessory)
app.run()
#else
print("AppLauncher's UI needs macOS. LauncherCore builds here; run `swift test` to exercise it.")
#endif

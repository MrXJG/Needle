import AppKit

@MainActor
final class NeedleAppDelegate: NSObject, NSApplicationDelegate {
    static var reopenHandler: (() -> Void)?
    static var settingsHandler: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.reopenHandler?()
        return false
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        Self.settingsHandler?()
    }
}

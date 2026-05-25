import AppKit
import SearchCore

@MainActor
final class NeedleAppDelegate: NSObject, NSApplicationDelegate {
    static var reopenHandler: (() -> Void)?
    static var settingsHandler: (() -> Void)?
    static var appSettingsProvider: (() -> AppSettings)?
    static var hideToBackgroundHandler: (() -> Void)?

    private static var allowImmediateTerminate = false
    private var lastQuitAttemptAt: Date?
    private let quitConfirmInterval: TimeInterval = 1.25

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.reopenHandler?()
        return false
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        Self.settingsHandler?()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.allowImmediateTerminate {
            Self.allowImmediateTerminate = false
            return .terminateNow
        }

        let appSettings = Self.appSettingsProvider?() ?? AppSettings()
        if appSettings.commandQHidesWindow {
            Self.hideToBackgroundHandler?()
            NSSound.beep()
            return .terminateCancel
        }

        let now = Date()
        if let lastQuitAttemptAt, now.timeIntervalSince(lastQuitAttemptAt) <= quitConfirmInterval {
            return .terminateNow
        }

        self.lastQuitAttemptAt = now
        NSSound.beep()
        return .terminateCancel
    }

    static func terminateNow() {
        allowImmediateTerminate = true
        NSApplication.shared.terminate(nil)
    }
}

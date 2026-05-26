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

    static func relaunchCurrentApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        task.arguments = [
            "/bin/sh",
            "-c",
            """
            pid="$1"
            app="$2"
            while /bin/kill -0 "$pid" 2>/dev/null; do
                /bin/sleep 0.1
            done
            /usr/bin/open "$app"
            """,
            "needle-relaunch",
            "\(ProcessInfo.processInfo.processIdentifier)",
            Bundle.main.bundleURL.path
        ]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exit(0)
        }
    }
}

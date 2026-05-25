import AppKit
import Carbon
import SearchCore

@MainActor
final class GlobalShortcutController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private weak var window: NSWindow?
    private lazy var windowDelegate = SearchWindowDelegate { [weak self] in
        self?.onWindowHidden?()
        Self.hideDockIcon()
    }
    private(set) var lastRegistrationStatus: OSStatus = noErr
    var onWindowHidden: (() -> Void)?
    var onWindowShown: (() -> Void)?

    func bind(window: NSWindow) {
        self.window = window
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
    }

    func update(settings: AppSettings) {
        windowDelegate.keepRunningAfterWindowClose = settings.keepRunningAfterWindowClose
        stop()
        guard settings.globalShortcutEnabled else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == GlobalShortcutController.signature else {
                    return noErr
                }

                let controller = Unmanaged<GlobalShortcutController>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    controller.showSearchWindow()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        lastRegistrationStatus = RegisterEventHotKey(
            UInt32(settings.globalShortcutKeyCode),
            UInt32(settings.carbonModifierFlags),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    func showSearchWindow() {
        onWindowShown?()
        Self.showDockIcon()
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.setIsVisible(true)
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    private static func showDockIcon() {
        NSApp.setActivationPolicy(.regular)
    }

    private static func hideDockIcon() {
        NSApp.setActivationPolicy(.accessory)
    }

    private static let signature: OSType = fourCharacterCode("Ndle")
}

private final class SearchWindowDelegate: NSObject, NSWindowDelegate {
    private let didCloseToBackground: () -> Void
    var keepRunningAfterWindowClose = true

    init(didCloseToBackground: @escaping () -> Void) {
        self.didCloseToBackground = didCloseToBackground
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard keepRunningAfterWindowClose else {
            return true
        }

        sender.orderOut(nil)
        didCloseToBackground()
        return false
    }
}

private extension AppSettings {
    var carbonModifierFlags: Int {
        var flags = 0
        let modifiers = NSEvent.ModifierFlags(rawValue: globalShortcutModifiers)
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        return flags
    }
}

private func fourCharacterCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { result, character in
        (result << 8) + OSType(character)
    }
}

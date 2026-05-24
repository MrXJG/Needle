import AppKit
import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultGlobalShortcutKeyCode: UInt16 = 3
    public static let defaultGlobalShortcutModifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue
    public static let legacyWrongGlobalShortcutModifiers: UInt = 786432

    public var launchAtLogin: Bool
    public var globalShortcutEnabled: Bool
    public var globalShortcutKeyCode: UInt16
    public var globalShortcutModifiers: UInt
    public var hasCompletedOnboarding: Bool
    public var keepRunningAfterWindowClose: Bool

    public init(
        launchAtLogin: Bool = false,
        globalShortcutEnabled: Bool = true,
        globalShortcutKeyCode: UInt16 = Self.defaultGlobalShortcutKeyCode,
        globalShortcutModifiers: UInt = Self.defaultGlobalShortcutModifiers,
        hasCompletedOnboarding: Bool = false,
        keepRunningAfterWindowClose: Bool = true
    ) {
        self.launchAtLogin = launchAtLogin
        self.globalShortcutEnabled = globalShortcutEnabled
        self.globalShortcutKeyCode = globalShortcutKeyCode
        self.globalShortcutModifiers = globalShortcutModifiers
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.keepRunningAfterWindowClose = keepRunningAfterWindowClose
    }

    public mutating func migrateIfNeeded() {
        if globalShortcutModifiers == Self.legacyWrongGlobalShortcutModifiers {
            globalShortcutModifiers = Self.defaultGlobalShortcutModifiers
        }
    }
}

public extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case globalShortcutEnabled
        case globalShortcutKeyCode
        case globalShortcutModifiers
        case hasCompletedOnboarding
        case keepRunningAfterWindowClose
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            globalShortcutEnabled: try container.decodeIfPresent(Bool.self, forKey: .globalShortcutEnabled) ?? true,
            globalShortcutKeyCode: try container.decodeIfPresent(UInt16.self, forKey: .globalShortcutKeyCode) ?? Self.defaultGlobalShortcutKeyCode,
            globalShortcutModifiers: try container.decodeIfPresent(UInt.self, forKey: .globalShortcutModifiers) ?? Self.defaultGlobalShortcutModifiers,
            hasCompletedOnboarding: try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false,
            keepRunningAfterWindowClose: try container.decodeIfPresent(Bool.self, forKey: .keepRunningAfterWindowClose) ?? true
        )
    }
}

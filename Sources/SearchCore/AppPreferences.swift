import Foundation

public final class AppPreferences: @unchecked Sendable {
    private let defaults: UserDefaults
    private let indexSettingsKey = "Needle.IndexSettings"
    private let appSettingsKey = "Needle.AppSettings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> IndexSettings {
        guard
            let data = defaults.data(forKey: indexSettingsKey),
            let settings = try? JSONDecoder().decode(IndexSettings.self, from: data)
        else {
            return IndexSettings()
        }
        var migratedSettings = settings
        migratedSettings.migrateIfNeeded()
        if migratedSettings != settings {
            save(migratedSettings)
        }
        return migratedSettings
    }

    public func save(_ settings: IndexSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: indexSettingsKey)
    }

    public func loadAppSettings() -> AppSettings {
        guard
            let data = defaults.data(forKey: appSettingsKey),
            var settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        settings.migrateIfNeeded()
        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: appSettingsKey)
    }
}

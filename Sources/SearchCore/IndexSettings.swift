import Foundation

public struct IndexSettings: Codable, Equatable, Sendable {
    public static let commonExcludedNamePatterns = [
        ".git",
        "node_modules",
        ".build",
        "Library/Caches",
        "Library/Logs",
        "DerivedData",
        ".codex",
        ".omx",
        ".swiftpm",
        ".DS_Store"
    ]
    private static let migratedExcludedNamePatterns = ["Library/Logs", ".codex", ".omx"]

    public var roots: [String]
    public var excludedPaths: [String]
    public var excludedNamePatterns: [String]
    public var includeHiddenFiles: Bool
    public var matchPathByDefault: Bool

    public init(
        roots: [String] = [],
        excludedPaths: [String] = [],
        excludedNamePatterns: [String] = Self.commonExcludedNamePatterns,
        includeHiddenFiles: Bool = false,
        matchPathByDefault: Bool = true
    ) {
        self.roots = roots
        self.excludedPaths = excludedPaths
        self.excludedNamePatterns = excludedNamePatterns
        self.includeHiddenFiles = includeHiddenFiles
        self.matchPathByDefault = matchPathByDefault
    }

    public func shouldIndex(path: String, name: String) -> Bool {
        if !includeHiddenFiles && name.hasPrefix(".") {
            return false
        }

        if excludedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return false
        }

        if excludedNamePatterns.contains(where: { pattern in
            name == pattern || path.contains("/\(pattern)/")
        }) {
            return false
        }

        return true
    }

    public func hasSameIndexScope(as other: IndexSettings) -> Bool {
        roots == other.roots
            && excludedPaths == other.excludedPaths
            && excludedNamePatterns == other.excludedNamePatterns
            && includeHiddenFiles == other.includeHiddenFiles
    }

    public mutating func migrateIfNeeded() {
        if excludedNamePatterns.isEmpty {
            excludedNamePatterns = Self.commonExcludedNamePatterns
            return
        }

        for pattern in Self.migratedExcludedNamePatterns where !excludedNamePatterns.contains(pattern) {
            excludedNamePatterns.append(pattern)
        }
    }
}

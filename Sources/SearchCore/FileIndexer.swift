import Foundation

public enum IndexerState: Equatable, Sendable {
    case idle
    case loading
    case scanning(processed: Int)
    case watching
    case permissionBlocked(String)
    case degraded(String)
}

public struct ScanResult: Sendable {
    public let records: [FileRecord]
    public let blockedPaths: [String]
}

public actor FileIndexer {
    private let fileManager: FileManager
    private let homeDirectory: URL

    public init(fileManager: FileManager = .default, homeDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
    }

    public func scan(settings: IndexSettings, progress: (@Sendable (Int) async -> Void)? = nil) async -> ScanResult {
        var records: [FileRecord] = []
        var blockedPaths: [String] = []
        var processed = 0

        for root in settings.roots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard fileManager.fileExists(atPath: rootURL.path) else {
                blockedPaths.append(rootURL.path)
                continue
            }
            blockedPaths.append(contentsOf: blockedProtectedHomeDescendants(under: rootURL))

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsPackageDescendants],
                errorHandler: { url, _ in
                    blockedPaths.append(url.path)
                    return true
                }
            ) else {
                blockedPaths.append(rootURL.path)
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                let name = url.lastPathComponent
                guard settings.shouldIndex(path: url.path, name: name) else {
                    enumerator.skipDescendants()
                    continue
                }

                if let record = FileRecord.fromFileURL(url) {
                    records.append(record)
                }

                processed += 1
                if processed.isMultiple(of: 500) {
                    await progress?(processed)
                }
            }

            for protectedURL in protectedHomeDescendants(under: rootURL) {
                let protectedRecords = scanSinglePath(protectedURL.path, settings: settings)
                records.append(contentsOf: protectedRecords)
            }

            for visibleURL in visibleHomeDescendants(under: rootURL, settings: settings) {
                let visibleRecords = scanSinglePath(visibleURL.path, settings: settings)
                records.append(contentsOf: visibleRecords)
            }
        }

        await progress?(processed)
        return ScanResult(records: deduplicatedRecords(records), blockedPaths: Array(Set(blockedPaths)).sorted())
    }

    public func scanSinglePath(_ path: String, settings: IndexSettings) -> [FileRecord] {
        let url = URL(fileURLWithPath: path)
        guard settings.shouldIndex(path: url.path, name: url.lastPathComponent) else {
            return []
        }

        var records: [FileRecord] = []
        if let record = FileRecord.fromFileURL(url) {
            records.append(record)
        }

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true else {
            return records
        }

        var pendingDirectories = [url]
        while let directoryURL = pendingDirectories.popLast() {
            guard let children = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isPackageKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: []
            ) else {
                continue
            }

            for childURL in children {
                guard settings.shouldIndex(path: childURL.path, name: childURL.lastPathComponent) else {
                    continue
                }
                if let record = FileRecord.fromFileURL(childURL) {
                    records.append(record)
                }
                guard let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else {
                    continue
                }
                if values.isDirectory == true && values.isPackage != true {
                    pendingDirectories.append(childURL)
                }
            }
        }

        return records
    }

    private func blockedProtectedHomeDescendants(under rootURL: URL) -> [String] {
        protectedHomeDescendants(under: rootURL).compactMap { url in
            guard fileManager.fileExists(atPath: url.path) else { return nil }

            do {
                _ = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                return nil
            } catch {
                return url.path
            }
        }
    }

    private func protectedHomeDescendants(under rootURL: URL) -> [URL] {
        let home = homeDirectory
        guard rootURL.path == home.path || home.path.hasPrefix(rootURL.path + "/") else {
            return []
        }

        let protectedNames = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
        return protectedNames.map {
            home.appendingPathComponent($0, isDirectory: true)
        }
    }

    private func visibleHomeDescendants(under rootURL: URL, settings: IndexSettings) -> [URL] {
        let home = homeDirectory
        guard rootURL.path == home.path else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let explicitlyHandledNames = Set(["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Library"])
        return children.filter { url in
            let name = url.lastPathComponent
            guard !explicitlyHandledNames.contains(name) else { return false }
            guard settings.shouldIndex(path: url.path, name: name) else { return false }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return false }
            return values.isDirectory == true && values.isPackage != true
        }
    }

    private func deduplicatedRecords(_ records: [FileRecord]) -> [FileRecord] {
        var recordsByPath: [String: FileRecord] = [:]
        recordsByPath.reserveCapacity(records.count)

        for record in records {
            recordsByPath[record.path] = record
        }

        return Array(recordsByPath.values)
    }
}

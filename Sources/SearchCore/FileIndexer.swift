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

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .volumeIdentifierKey
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
        }

        await progress?(processed)
        return ScanResult(records: records, blockedPaths: blockedPaths)
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

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .volumeIdentifierKey
            ],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return records
        }

        while let childURL = enumerator.nextObject() as? URL {
            guard settings.shouldIndex(path: childURL.path, name: childURL.lastPathComponent) else {
                enumerator.skipDescendants()
                continue
            }
            if let record = FileRecord.fromFileURL(childURL) {
                records.append(record)
            }
        }

        return records
    }
}

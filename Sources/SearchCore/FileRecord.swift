import Foundation

public enum FileKind: String, Codable, Sendable, CaseIterable {
    case file
    case folder
    case other
}

public struct FileRecord: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let path: String
    public let name: String
    public let parentPath: String
    public let kind: FileKind
    public let ext: String
    public let size: Int64
    public let modifiedAt: Date
    public let volumeIdentifier: String
    public var openCount: Int
    public var lastOpenedAt: Date?

    public init(
        path: String,
        name: String,
        parentPath: String,
        kind: FileKind,
        ext: String,
        size: Int64,
        modifiedAt: Date,
        volumeIdentifier: String,
        openCount: Int = 0,
        lastOpenedAt: Date? = nil
    ) {
        self.id = path
        self.path = path
        self.name = name
        self.parentPath = parentPath
        self.kind = kind
        self.ext = ext
        self.size = size
        self.modifiedAt = modifiedAt
        self.volumeIdentifier = volumeIdentifier
        self.openCount = openCount
        self.lastOpenedAt = lastOpenedAt
    }
}

public extension FileRecord {
    static func fromFileURL(_ url: URL, resourceValues: URLResourceValues? = nil) -> FileRecord? {
        let values: URLResourceValues
        do {
            values = try resourceValues ?? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .volumeIdentifierKey
            ])
        } catch {
            return nil
        }

        let kind: FileKind
        if values.isDirectory == true {
            kind = .folder
        } else if values.isRegularFile == true {
            kind = .file
        } else {
            kind = .other
        }

        let volumeIdentifier: String
        if let volume = values.volumeIdentifier {
            volumeIdentifier = String(describing: volume)
        } else {
            volumeIdentifier = "unknown"
        }

        return FileRecord(
            path: url.path,
            name: url.lastPathComponent,
            parentPath: url.deletingLastPathComponent().path,
            kind: kind,
            ext: url.pathExtension.lowercased(),
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast,
            volumeIdentifier: volumeIdentifier
        )
    }
}

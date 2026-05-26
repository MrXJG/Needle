import Foundation

public enum FileKind: String, Codable, Sendable, CaseIterable {
    case file
    case folder
    case other
}

public struct FileRecord: Identifiable, Equatable, Codable, Sendable {
    public let path: String
    public let name: String
    public let kind: FileKind
    public let ext: String
    public let size: Int64
    public let modifiedAt: Date
    public var openCount: Int
    public var lastOpenedAt: Date?

    public var id: String { path }
    public var isApplicationBundle: Bool {
        kind == .folder && ext == "app"
    }

    public var parentPath: String {
        guard let slashIndex = path.lastIndex(of: "/"), slashIndex != path.startIndex else {
            return "/"
        }
        return String(path[..<slashIndex])
    }

    public init(
        path: String,
        name: String,
        parentPath: String,
        kind: FileKind,
        ext: String,
        size: Int64,
        modifiedAt: Date,
        volumeIdentifier: String = "",
        openCount: Int = 0,
        lastOpenedAt: Date? = nil
    ) {
        self.path = path
        self.name = name
        self.kind = kind
        self.ext = ext
        self.size = size
        self.modifiedAt = modifiedAt
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
                .contentModificationDateKey
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

        return FileRecord(
            path: url.path,
            name: url.lastPathComponent,
            parentPath: url.deletingLastPathComponent().path,
            kind: kind,
            ext: url.pathExtension.lowercased(),
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast
        )
    }
}

import Foundation
#if canImport(CoreServices)
import CoreServices
#endif

public enum FileKind: String, Codable, Sendable, CaseIterable {
    case file
    case folder
    case other
}

public struct FileRecord: Identifiable, Equatable, Codable, Sendable {
    public let path: String
    public let name: String
    public let displayName: String
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

    public var displayLabel: String {
        displayName.isEmpty ? name : displayName
    }

    public var parentPath: String {
        guard let slashIndex = path.lastIndex(of: "/"), slashIndex != path.startIndex else {
            return "/"
        }
        return String(path[..<slashIndex])
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case name
        case displayName
        case kind
        case ext
        case size
        case modifiedAt
        case openCount
        case lastOpenedAt
    }

    public init(
        path: String,
        name: String,
        parentPath: String,
        displayName: String = "",
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
        self.displayName = displayName
        self.kind = kind
        self.ext = ext
        self.size = size
        self.modifiedAt = modifiedAt
        self.openCount = openCount
        self.lastOpenedAt = lastOpenedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.name = try container.decode(String.self, forKey: .name)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        self.kind = try container.decode(FileKind.self, forKey: .kind)
        self.ext = try container.decode(String.self, forKey: .ext)
        self.size = try container.decode(Int64.self, forKey: .size)
        self.modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        self.openCount = try container.decodeIfPresent(Int.self, forKey: .openCount) ?? 0
        self.lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(kind, forKey: .kind)
        try container.encode(ext, forKey: .ext)
        try container.encode(size, forKey: .size)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(openCount, forKey: .openCount)
        try container.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
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
            displayName: localizedDisplayName(forPath: url.path, kind: kind, ext: url.pathExtension.lowercased()),
            kind: kind,
            ext: url.pathExtension.lowercased(),
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast
        )
    }

    static func localizedDisplayName(forPath path: String, kind: FileKind, ext: String) -> String {
        guard kind == .folder, ext == "app" else {
            return ""
        }

#if canImport(CoreServices)
        guard let item = MDItemCreate(nil, path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemDisplayName) as? String,
              !value.isEmpty else {
            return ""
        }
        return value
#else
        return ""
#endif
    }
}

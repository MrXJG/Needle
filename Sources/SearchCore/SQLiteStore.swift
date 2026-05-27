import Foundation
import SQLite3

public enum SQLiteStoreError: Error, LocalizedError, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "SQLite open failed: \(message)"
        case .prepareFailed(let message):
            return "SQLite prepare failed: \(message)"
        case .executeFailed(let message):
            return "SQLite execute failed: \(message)"
        }
    }
}

public actor SQLiteStore {
    private let databaseURL: URL
    private var db: OpaquePointer?

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    public func open() throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        if sqlite3_open(databaseURL.path, &handle) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw SQLiteStoreError.openFailed(message)
        }
        db = handle

        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("""
        CREATE TABLE IF NOT EXISTS files (
            path TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            display_name TEXT NOT NULL DEFAULT '',
            parent_path TEXT NOT NULL,
            kind TEXT NOT NULL,
            ext TEXT NOT NULL,
            size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            volume_identifier TEXT NOT NULL,
            open_count INTEGER NOT NULL DEFAULT 0,
            last_opened_at REAL
        );
        """)
        try execute("ALTER TABLE files ADD COLUMN last_opened_at REAL;", ignoringMessageContaining: "duplicate column name")
        try execute("ALTER TABLE files ADD COLUMN display_name TEXT NOT NULL DEFAULT '';", ignoringMessageContaining: "duplicate column name")
        try execute("CREATE INDEX IF NOT EXISTS idx_files_name ON files(name);")
        try execute("CREATE INDEX IF NOT EXISTS idx_files_display_name ON files(display_name);")
        try execute("CREATE INDEX IF NOT EXISTS idx_files_ext ON files(ext);")
    }

    public func replaceAll(with records: [FileRecord]) throws {
        let existingRecords = try loadAll()
        let openStatsByPath = Dictionary(uniqueKeysWithValues: existingRecords.map {
            ($0.path, (openCount: $0.openCount, lastOpenedAt: $0.lastOpenedAt))
        })
        let recordsWithPreservedOpenStats = records.map { record in
            var record = record
            if let stats = openStatsByPath[record.path] {
                record.openCount = stats.openCount
                record.lastOpenedAt = stats.lastOpenedAt
            }
            return record
        }

        try execute("BEGIN TRANSACTION;")
        do {
            try execute("DELETE FROM files;")
            try upsert(recordsWithPreservedOpenStats)
            try execute("COMMIT;")
            try? checkpointAndTruncateWAL()
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func checkpointAndTruncateWAL() throws {
        try execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    public func upsert(_ records: [FileRecord]) throws {
        guard !records.isEmpty else { return }
        let sql = """
        INSERT INTO files
            (path, name, display_name, parent_path, kind, ext, size, modified_at, volume_identifier, open_count, last_opened_at)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            name = excluded.name,
            display_name = excluded.display_name,
            parent_path = excluded.parent_path,
            kind = excluded.kind,
            ext = excluded.ext,
            size = excluded.size,
            modified_at = excluded.modified_at,
            volume_identifier = excluded.volume_identifier;
        """

        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        for record in records {
            bind(record, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.executeFailed(lastErrorMessage)
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    public func replaceSubtrees(paths: [String], with records: [FileRecord]) throws {
        try execute("BEGIN TRANSACTION;")
        do {
            try delete(paths: paths)
            try upsert(records)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func delete(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        var statement: OpaquePointer?
        try prepare("DELETE FROM files WHERE path = ? OR (path >= ? AND path < ?);", statement: &statement)
        defer { sqlite3_finalize(statement) }

        for path in paths {
            let lowerBound = path + "/"
            let upperBound = lowerBound + "\u{10FFFF}"
            sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, lowerBound, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, upperBound, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteStoreError.executeFailed(lastErrorMessage)
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
    }

    public func incrementOpenCount(path: String) throws {
        try recordOpen(path: path)
    }

    public func recordOpen(path: String, at date: Date = Date()) throws {
        var statement: OpaquePointer?
        try prepare("UPDATE files SET open_count = open_count + 1, last_opened_at = ? WHERE path = ?;", statement: &statement)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        sqlite3_bind_text(statement, 2, path, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.executeFailed(lastErrorMessage)
        }
    }

    public func loadAll() throws -> [FileRecord] {
        let sql = """
        SELECT path, name, display_name, kind, ext, size, modified_at, open_count, last_opened_at
        FROM files;
        """
        return try loadRecords(sql: sql)
    }

    public func loadPreview(limit: Int) throws -> [FileRecord] {
        guard limit > 0 else { return [] }
        let sql = """
        SELECT path, name, display_name, kind, ext, size, modified_at, open_count, last_opened_at
        FROM files
        LIMIT \(limit);
        """
        return try loadRecords(sql: sql)
    }

    public func searchCandidates(query: SearchQuery, limit: Int) throws -> [FileRecord] {
        guard limit > 0 else { return [] }
        guard query.invalidRegexPatterns.isEmpty else { return [] }
        guard !query.terms.isEmpty || query.extensionFilter != nil else { return [] }

        var clauses: [String] = []
        var bindings: [String] = []

        switch query.kindFilter {
        case .all:
            break
        case .files:
            clauses.append("kind = ?")
            bindings.append(FileKind.file.rawValue)
        case .folders:
            clauses.append("kind = ?")
            bindings.append(FileKind.folder.rawValue)
        }

        if let extensionFilter = query.extensionFilter {
            clauses.append("ext = ?")
            bindings.append(extensionFilter)
        }

        for term in query.terms {
            let likePattern = "%\(escapedLikePattern(term))%"
            let searchableColumns = query.matchPath
                ? ["name", "display_name", "path"]
                : ["name", "display_name"]
            clauses.append(
                searchableColumns
                    .map { "\($0) LIKE ? COLLATE NOCASE ESCAPE '\\'" }
                    .joined(separator: " OR ")
                    .wrappedInParentheses()
            )
            bindings.append(contentsOf: Array(repeating: likePattern, count: searchableColumns.count))
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE \(clauses.joined(separator: " AND "))"
        let orderClause: String
        if let firstTerm = query.terms.first {
            orderClause = """
            ORDER BY
                CASE
                    WHEN name = ? COLLATE NOCASE OR display_name = ? COLLATE NOCASE THEN 0
                    WHEN name LIKE ? COLLATE NOCASE ESCAPE '\\' OR display_name LIKE ? COLLATE NOCASE ESCAPE '\\' THEN 1
                    WHEN name LIKE ? COLLATE NOCASE ESCAPE '\\' OR display_name LIKE ? COLLATE NOCASE ESCAPE '\\' THEN 2
                    ELSE 3
                END,
                length(path) ASC,
                modified_at DESC
            """
            let escapedFirstTerm = escapedLikePattern(firstTerm)
            bindings.append(firstTerm)
            bindings.append(firstTerm)
            bindings.append("\(escapedFirstTerm)%")
            bindings.append("\(escapedFirstTerm)%")
            bindings.append("%\(escapedFirstTerm)%")
            bindings.append("%\(escapedFirstTerm)%")
        } else {
            orderClause = "ORDER BY length(path) ASC, modified_at DESC"
        }
        let sql = """
        SELECT path, name, display_name, kind, ext, size, modified_at, open_count, last_opened_at
        FROM files
        \(whereClause)
        \(orderClause)
        LIMIT \(limit);
        """

        return try loadRecords(sql: sql, bindings: bindings)
    }

    public func recordCount() throws -> Int {
        var statement: OpaquePointer?
        try prepare("SELECT COUNT(*) FROM files;", statement: &statement)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteStoreError.executeFailed(lastErrorMessage)
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func loadRecords(sql: String, bindings: [String] = []) throws -> [FileRecord] {
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

        for (index, binding) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), binding, -1, SQLITE_TRANSIENT)
        }

        var records: [FileRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(readRecord(from: statement))
        }
        return records
    }

    private func execute(_ sql: String) throws {
        guard let db else {
            throw SQLiteStoreError.openFailed("database is not open")
        }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(error)
            throw SQLiteStoreError.executeFailed(message)
        }
    }

    private func execute(_ sql: String, ignoringMessageContaining ignoredMessage: String) throws {
        do {
            try execute(sql)
        } catch SQLiteStoreError.executeFailed(let message) where message.localizedCaseInsensitiveContains(ignoredMessage) {
            return
        }
    }

    private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
        guard let db else {
            throw SQLiteStoreError.openFailed("database is not open")
        }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.prepareFailed(lastErrorMessage)
        }
    }

    private var lastErrorMessage: String {
        guard let db else { return "database is not open" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func bind(_ record: FileRecord, to statement: OpaquePointer?) {
        sqlite3_bind_text(statement, 1, record.path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, record.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, record.displayName, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, record.parentPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, record.kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, record.ext, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 7, record.size)
        sqlite3_bind_double(statement, 8, record.modifiedAt.timeIntervalSince1970)
        sqlite3_bind_text(statement, 9, "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 10, Int32(record.openCount))
        if let lastOpenedAt = record.lastOpenedAt {
            sqlite3_bind_double(statement, 11, lastOpenedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 11)
        }
    }

    private func readRecord(from statement: OpaquePointer?) -> FileRecord {
        let path = text(statement, 0)
        let name = text(statement, 1)
        let storedDisplayName = text(statement, 2)
        let kind = FileKind(rawValue: text(statement, 3)) ?? .other
        let ext = text(statement, 4)
        let displayName = storedDisplayName.isEmpty
            ? FileRecord.localizedDisplayName(forPath: path, kind: kind, ext: ext)
            : storedDisplayName

        return FileRecord(
            path: path,
            name: name,
            parentPath: "",
            displayName: displayName,
            kind: kind,
            ext: ext,
            size: sqlite3_column_int64(statement, 5),
            modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            openCount: Int(sqlite3_column_int(statement, 7)),
            lastOpenedAt: optionalDate(statement, 8)
        )
    }

    private func optionalDate(_ statement: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private func escapedLikePattern(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    func wrappedInParentheses() -> String {
        "(\(self))"
    }
}

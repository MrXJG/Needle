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
        try execute("CREATE INDEX IF NOT EXISTS idx_files_name ON files(name);")
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
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func upsert(_ records: [FileRecord]) throws {
        guard !records.isEmpty else { return }
        let sql = """
        INSERT INTO files
            (path, name, parent_path, kind, ext, size, modified_at, volume_identifier, open_count, last_opened_at)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            name = excluded.name,
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

    public func delete(paths: [String]) throws {
        guard !paths.isEmpty else { return }
        var statement: OpaquePointer?
        try prepare("DELETE FROM files WHERE path = ? OR path LIKE ?;", statement: &statement)
        defer { sqlite3_finalize(statement) }

        for path in paths {
            sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, path + "/%", -1, SQLITE_TRANSIENT)
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
        SELECT path, name, parent_path, kind, ext, size, modified_at, volume_identifier, open_count, last_opened_at
        FROM files;
        """
        var statement: OpaquePointer?
        try prepare(sql, statement: &statement)
        defer { sqlite3_finalize(statement) }

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
        sqlite3_bind_text(statement, 3, record.parentPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, record.kind.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, record.ext, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 6, record.size)
        sqlite3_bind_double(statement, 7, record.modifiedAt.timeIntervalSince1970)
        sqlite3_bind_text(statement, 8, record.volumeIdentifier, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 9, Int32(record.openCount))
        if let lastOpenedAt = record.lastOpenedAt {
            sqlite3_bind_double(statement, 10, lastOpenedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 10)
        }
    }

    private func readRecord(from statement: OpaquePointer?) -> FileRecord {
        FileRecord(
            path: text(statement, 0),
            name: text(statement, 1),
            parentPath: text(statement, 2),
            kind: FileKind(rawValue: text(statement, 3)) ?? .other,
            ext: text(statement, 4),
            size: sqlite3_column_int64(statement, 5),
            modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            volumeIdentifier: text(statement, 7),
            openCount: Int(sqlite3_column_int(statement, 8)),
            lastOpenedAt: optionalDate(statement, 9)
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
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

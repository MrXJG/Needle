import Foundation
import SearchCore

@main
struct NeedleCoreCheck {
    static func main() async throws {
        try checkQueryParsing()
        try checkRanking()
        try checkFilters()
        try checkPatternSearch()
        try checkExclusions()
        try checkLargeIndexSearchPerformance()
        try await checkSQLite()
        print("NeedleCoreCheck passed")
    }

    private static func checkQueryParsing() throws {
        let query = SearchQuery.parse("\"project notes\" ext:md draft")
        try expect(query.terms == ["project notes", "draft"], "quoted terms should be preserved")
        try expect(query.extensionFilter == "md", "extension filter should parse")
        try expect(query.wildcardPatterns.isEmpty, "plain extension query should not create wildcard patterns")
        try expect(query.regexPatterns.isEmpty, "plain extension query should not create regex patterns")
        try expect(query.kindFilter == .all, "default kind should be all")
        try expect(query.matchPath, "path matching should default on")

        let patternQuery = SearchQuery.parse(".rpm *.tar.gz re:^readme\\.(md|txt)$")
        try expect(patternQuery.extensionFilter == "rpm", "dot extension shortcut should parse")
        try expect(patternQuery.wildcardPatterns == ["*.tar.gz"], "wildcard pattern should parse")
        try expect(patternQuery.regexPatterns == ["^readme\\.(md|txt)$"], "regex pattern should parse")
    }

    private static func checkRanking() throws {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/Users/me/archive/report.txt", name: "report.txt"),
            makeRecord(path: "/Users/me/reporting/archive.txt", name: "archive.txt")
        ]
        let results = engine.search(records, query: .parse("report"))
        try expect(results.first?.name == "report.txt", "filename prefix should outrank path-only match")

        let preferredResults = engine.search(
            [
                makeRecord(path: "/Users/me/archive/report.txt", name: "report.txt"),
                makeRecord(path: "/Users/me/work/report.txt", name: "report.txt")
            ],
            query: .parse("report"),
            preferredFolderPaths: ["/Users/me/work"]
        )
        try expect(preferredResults.first?.path == "/Users/me/work/report.txt", "preferred indexed roots should boost nearby results")
    }

    private static func checkFilters() throws {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/tmp/App.swift", name: "App.swift", kind: .file, ext: "swift"),
            makeRecord(path: "/tmp/App", name: "App", kind: .folder, ext: ""),
            makeRecord(path: "/Applications/WeChat.app", name: "WeChat.app", displayName: "微信.app", kind: .folder, ext: "app")
        ]
        let query = SearchQuery.parse("app ext:swift", kindFilter: .files)
        let results = engine.search(records, query: query)
        try expect(results.map(\.path) == ["/tmp/App.swift"], "kind and extension filters should combine")
        try expect(engine.search(records, query: .parse("微信.app")).map(\.path) == ["/Applications/WeChat.app"], "localized app display names should be searchable")
    }

    private static func checkPatternSearch() throws {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/tmp/pkg/app.rpm", name: "app.rpm", ext: "rpm"),
            makeRecord(path: "/tmp/pkg/readme.txt", name: "readme.txt", ext: "txt"),
            makeRecord(path: "/tmp/pkg/archive.tar.gz", name: "archive.tar.gz", ext: "gz")
        ]

        try expect(engine.search(records, query: .parse("*.rpm")).map(\.path) == ["/tmp/pkg/app.rpm"], "wildcard search should match filenames")
        try expect(engine.search(records, query: .parse(".txt")).map(\.path) == ["/tmp/pkg/readme.txt"], "dot extension shortcut should filter extensions")
        try expect(engine.search(records, query: .parse("re:^archive\\.tar\\.gz$")).map(\.path) == ["/tmp/pkg/archive.tar.gz"], "regex search should match filenames")
    }

    private static func checkExclusions() throws {
        let settings = IndexSettings(excludedNamePatterns: [".git", "node_modules"])
        try expect(!settings.shouldIndex(path: "/tmp/.env", name: ".env"), "hidden files should be skipped")
        try expect(!settings.shouldIndex(path: "/tmp/project/node_modules/pkg", name: "pkg"), "excluded folders should be skipped")
        try expect(settings.shouldIndex(path: "/tmp/project/Sources/App.swift", name: "App.swift"), "normal files should be indexed")
    }

    private static func checkLargeIndexSearchPerformance() throws {
        let engine = SearchEngine()
        let records = (0..<100_000).map { index in
            makeRecord(
                path: "/tmp/needle-large-index/project-\(index % 200)/file-\(index).swift",
                name: "file-\(index).swift",
                ext: "swift"
            )
        } + [
            makeRecord(path: "/tmp/needle-large-index/favorites/needle-target.swift", name: "needle-target.swift", ext: "swift")
        ]
        let cachedRecords = records.enumerated().map { index, record in
            SearchRecord(record: record, index: index)
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        let results = engine.search(cachedRecords, records: records, query: .parse("needle-target .swift"), preferredFolderPaths: ["/tmp/needle-large-index/favorites"])
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000

        try expect(results.first?.name == "needle-target.swift", "large-index search should find the intended result")
        try expect(elapsedMS < 1_000, "cached large-index search should complete under 1 second, actual \(elapsedMS) ms")
    }

    private static func checkSQLite() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("index.sqlite")
        let store = SQLiteStore(databaseURL: url)
        try await store.open()
        try await store.upsert([
            makeRecord(path: "/tmp/Readme.md", name: "Readme.md", displayName: "说明.md", ext: "md")
        ])
        try await store.recordOpen(path: "/tmp/Readme.md", at: Date(timeIntervalSince1970: 1_750_000_000))
        let records = try await store.loadAll()
        try expect(records.count == 1, "SQLite should load inserted record")
        try expect(records.first?.displayName == "说明.md", "SQLite should persist display name")
        try expect(records.first?.openCount == 1, "SQLite should persist open count")
        try expect(records.first?.lastOpenedAt == Date(timeIntervalSince1970: 1_750_000_000), "SQLite should persist last opened time")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw CheckFailure(message)
        }
    }

    private static func makeRecord(
        path: String,
        name: String,
        displayName: String = "",
        kind: FileKind = .file,
        ext: String = "txt"
    ) -> FileRecord {
        FileRecord(
            path: path,
            name: name,
            parentPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
            displayName: displayName,
            kind: kind,
            ext: ext,
            size: 100,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            volumeIdentifier: "test"
        )
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

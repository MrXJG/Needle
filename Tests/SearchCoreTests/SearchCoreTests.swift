import Foundation
@testable import SearchCore
import XCTest

final class SearchCoreTests: XCTestCase {
    func testParsesTermsQuotesAndExtensionFilter() {
        let query = SearchQuery.parse("\"project notes\" ext:md draft")

        XCTAssertEqual(query.terms, ["project notes", "draft"])
        XCTAssertEqual(query.extensionFilter, "md")
        XCTAssertEqual(query.wildcardPatterns, [])
        XCTAssertEqual(query.regexPatterns, [])
        XCTAssertEqual(query.kindFilter, .all)
        XCTAssertTrue(query.matchPath)
    }

    func testParsesDotExtensionWildcardAndRegex() {
        let query = SearchQuery.parse(".rpm *.tar.gz re:^readme\\.(md|txt)$")

        XCTAssertEqual(query.extensionFilter, "rpm")
        XCTAssertEqual(query.wildcardPatterns, ["*.tar.gz"])
        XCTAssertEqual(query.regexPatterns, ["^readme\\.(md|txt)$"])
        XCTAssertEqual(query.invalidRegexPatterns, [])
        XCTAssertEqual(query.kindFilter, .all)
        XCTAssertTrue(query.matchPath)
    }

    func testInvalidRegexProducesValidationMessage() {
        let query = SearchQuery.parse("re:[")

        XCTAssertEqual(query.regexPatterns, [])
        XCTAssertEqual(query.invalidRegexPatterns, ["["])
        XCTAssertEqual(query.validationMessage, "正则表达式无效：[")
    }

    func testRanksPrefixMatchesBeforePathMatches() {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/Users/me/archive/report.txt", name: "report.txt"),
            makeRecord(path: "/Users/me/reporting/archive.txt", name: "archive.txt")
        ]

        let results = engine.search(records, query: .parse("report"))

        XCTAssertEqual(results.first?.name, "report.txt")
    }

    func testRanksStemExactMatchesBeforeLooseNameMatches() {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/Users/me/archive/old-report.txt", name: "old-report.txt"),
            makeRecord(path: "/Users/me/reports/reporting.txt", name: "reporting.txt", openCount: 12),
            makeRecord(path: "/Users/me/reports/report.pdf", name: "report.pdf", ext: "pdf"),
            makeRecord(path: "/Users/me/report/archive.txt", name: "archive.txt")
        ]

        let results = engine.search(records, query: .parse("report"))

        XCTAssertEqual(results.first?.name, "report.pdf")
    }

    func testOpenHistoryBreaksTiesWithinSimilarMatchQuality() {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/Users/me/reports/report-alpha.txt", name: "report-alpha.txt", openCount: 1),
            makeRecord(path: "/Users/me/reports/report-beta.txt", name: "report-beta.txt", openCount: 8)
        ]

        let results = engine.search(records, query: .parse("report"))

        XCTAssertEqual(results.first?.name, "report-beta.txt")
    }

    func testRecentOpenBreaksTiesWithinSimilarMatchQuality() {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/Users/me/reports/report-alpha.txt", name: "report-alpha.txt", lastOpenedAt: Date().addingTimeInterval(-86_400 * 20)),
            makeRecord(path: "/Users/me/reports/report-beta.txt", name: "report-beta.txt", lastOpenedAt: Date())
        ]

        let results = engine.search(records, query: .parse("report"))

        XCTAssertEqual(results.first?.name, "report-beta.txt")
    }

    func testPreferredFolderBoostsNearbyResults() {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/Users/me/archive/report.txt", name: "report.txt"),
            makeRecord(path: "/Users/me/work/report.txt", name: "report.txt")
        ]

        let results = engine.search(records, query: .parse("report"), preferredFolderPaths: ["/Users/me/work"])

        XCTAssertEqual(results.first?.path, "/Users/me/work/report.txt")
    }

    func testSearchLimitKeepsHighestRankedResults() {
        let engine = SearchEngine()
        let records = (0..<80).map { index in
            makeRecord(path: "/Users/me/archive/report-\(index).txt", name: "report-\(index).txt", openCount: index)
        }

        let results = engine.search(records, query: .parse("report"), limit: 5)

        XCTAssertEqual(results.map(\.openCount), [79, 78, 77, 76, 75])
    }

    func testFiltersByKindAndExtension() {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/tmp/App.swift", name: "App.swift", kind: .file, ext: "swift"),
            makeRecord(path: "/tmp/App", name: "App", kind: .folder, ext: "")
        ]

        let query = SearchQuery.parse("app ext:swift", kindFilter: .files)
        let results = engine.search(records, query: query)

        XCTAssertEqual(results.map(\.path), ["/tmp/App.swift"])
    }

    func testFiltersByWildcardAndRegex() {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/tmp/pkg/app.rpm", name: "app.rpm", ext: "rpm"),
            makeRecord(path: "/tmp/pkg/readme.txt", name: "readme.txt", ext: "txt"),
            makeRecord(path: "/tmp/pkg/archive.tar.gz", name: "archive.tar.gz", ext: "gz")
        ]

        let wildcardResults = engine.search(records, query: .parse("*.rpm"))
        XCTAssertEqual(wildcardResults.map(\.path), ["/tmp/pkg/app.rpm"])

        let dotExtResults = engine.search(records, query: .parse(".txt"))
        XCTAssertEqual(dotExtResults.map(\.path), ["/tmp/pkg/readme.txt"])

        let regexResults = engine.search(records, query: .parse("re:^archive\\.tar\\.gz$"))
        XCTAssertEqual(regexResults.map(\.path), ["/tmp/pkg/archive.tar.gz"])
    }

    func testSearchMatchesDottedUnderscoreReleaseNames() {
        let engine = SearchEngine()
        let records = [
            makeRecord(path: "/Users/me/Downloads/PlayCover_3.1.0.dmg", name: "PlayCover_3.1.0.dmg", ext: "dmg")
        ]

        let query = SearchQuery.parse("PlayCover_3.1.0")
        let results = engine.search(records, query: query)

        XCTAssertEqual(query.terms, ["playcover_3.1.0"])
        XCTAssertEqual(results.map(\.path), ["/Users/me/Downloads/PlayCover_3.1.0.dmg"])
    }

    @MainActor
    func testRebuildRefreshesResultsBeforeReportingCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = directory.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let fileURL = downloads.appendingPathComponent("PlayCover_3.1.0.dmg")
        try Data("fixture".utf8).write(to: fileURL)

        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        let model = SearchAppModel(databaseURL: databaseURL, preferences: AppPreferences(defaults: defaults))
        model.settings = IndexSettings(roots: [directory.path], excludedNamePatterns: [], includeHiddenFiles: false)
        model.queryText = "PlayCover_3.1.0"

        await model.start()
        await model.rebuildIndex()

        XCTAssertEqual(model.state, .watching)
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(model.results.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }, [fileURL.standardizedFileURL.path])

        model.queryText = "missing"
        XCTAssertFalse(model.isSearching)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(model.isSearching)

        try? FileManager.default.removeItem(at: directory)
    }

    func testSettingsDefaultToNoRootsForSafeFirstLaunch() {
        let settings = IndexSettings()

        XCTAssertTrue(settings.roots.isEmpty)
    }

    func testSettingsDefaultToCommonExclusions() {
        let settings = IndexSettings()

        XCTAssertEqual(settings.excludedNamePatterns, IndexSettings.commonExcludedNamePatterns)
        XCTAssertTrue(settings.excludedNamePatterns.contains("node_modules"))
        XCTAssertTrue(settings.excludedNamePatterns.contains("DerivedData"))
    }

    func testAppSettingsDecodeLegacyPayloadKeepsBackgroundDefaultEnabled() throws {
        let legacyPayload = """
        {
          "launchAtLogin": false,
          "globalShortcutEnabled": true,
          "globalShortcutKeyCode": 3,
          "globalShortcutModifiers": 1179648,
          "hasCompletedOnboarding": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyPayload)

        XCTAssertTrue(settings.keepRunningAfterWindowClose)
    }

    func testSettingsExcludeHiddenAndConfiguredNames() {
        let settings = IndexSettings(excludedNamePatterns: [".git", "node_modules"])

        XCTAssertFalse(settings.shouldIndex(path: "/tmp/.env", name: ".env"))
        XCTAssertFalse(settings.shouldIndex(path: "/tmp/project/node_modules/pkg", name: "pkg"))
        XCTAssertTrue(settings.shouldIndex(path: "/tmp/project/Sources/App.swift", name: "App.swift"))
    }

    func testSettingsExcludeCustomPathFragments() {
        let settings = IndexSettings(excludedNamePatterns: ["dist", "Library/Caches"])

        XCTAssertFalse(settings.shouldIndex(path: "/tmp/site/dist/index.html", name: "index.html"))
        XCTAssertFalse(settings.shouldIndex(path: "/Users/me/Library/Caches/cache.db", name: "cache.db"))
        XCTAssertTrue(settings.shouldIndex(path: "/tmp/site/src/index.html", name: "index.html"))
    }

    func testIndexScopeComparisonIgnoresSearchOnlySettings() {
        var original = IndexSettings(roots: ["/tmp/project"])
        var changedSearchBehavior = original
        changedSearchBehavior.matchPathByDefault.toggle()

        XCTAssertTrue(original.hasSameIndexScope(as: changedSearchBehavior))

        original.excludedNamePatterns.append("dist")

        XCTAssertFalse(original.hasSameIndexScope(as: changedSearchBehavior))
    }

    func testSQLitePersistsRecordsAndOpenCount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("index.sqlite")
        let store = SQLiteStore(databaseURL: url)
        try await store.open()

        try await store.upsert([
            makeRecord(path: "/tmp/Readme.md", name: "Readme.md", ext: "md")
        ])
        let openedAt = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.recordOpen(path: "/tmp/Readme.md", at: openedAt)

        let records = try await store.loadAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.openCount, 1)
        XCTAssertEqual(records.first?.lastOpenedAt, openedAt)

        try? FileManager.default.removeItem(at: directory)
    }

    func testSQLiteReplaceSubtreesDeletesChildrenAndUpsertsRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("index.sqlite")
        let store = SQLiteStore(databaseURL: url)
        try await store.open()

        try await store.upsert([
            makeRecord(path: "/tmp/project", name: "project", kind: .folder, ext: ""),
            makeRecord(path: "/tmp/project/old.txt", name: "old.txt"),
            makeRecord(path: "/tmp/project/nested/old.txt", name: "old.txt"),
            makeRecord(path: "/tmp/project-sibling/keep.txt", name: "keep.txt")
        ])

        try await store.replaceSubtrees(
            paths: ["/tmp/project"],
            with: [makeRecord(path: "/tmp/project/new.txt", name: "new.txt")]
        )

        let paths = try await store.loadAll().map(\.path).sorted()
        XCTAssertEqual(paths, ["/tmp/project-sibling/keep.txt", "/tmp/project/new.txt"])

        try? FileManager.default.removeItem(at: directory)
    }
}

private func makeRecord(
    path: String,
    name: String,
    kind: FileKind = .file,
    ext: String = "txt",
    openCount: Int = 0,
    lastOpenedAt: Date? = nil
) -> FileRecord {
    FileRecord(
        path: path,
        name: name,
        parentPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
        kind: kind,
        ext: ext,
        size: 100,
        modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        volumeIdentifier: "test",
        openCount: openCount,
        lastOpenedAt: lastOpenedAt
    )
}

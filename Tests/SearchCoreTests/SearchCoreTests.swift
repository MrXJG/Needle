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

    func testEmptySearchReturnsInitialWindowWithoutRankingWholeIndex() {
        let engine = SearchEngine()
        let records = (0..<20).map { index in
            makeRecord(path: "/Users/me/file-\(index).txt", name: "file-\(index).txt", openCount: 20 - index)
        }

        let results = engine.search(records, query: .parse(""), limit: 5)

        XCTAssertEqual(results.map(\.path), Array(records.prefix(5)).map(\.path))
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
        let model = SearchAppModel(
            databaseURL: databaseURL,
            preferences: AppPreferences(defaults: defaults)
        )
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

    @MainActor
    func testRebuildExcludesNeedleInternalDatabaseDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appSupport = directory.appendingPathComponent("AppSupport", isDirectory: true)
        let databaseURL = appSupport.appendingPathComponent("Needle/index.sqlite")
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        let rootFile = directory.appendingPathComponent("visible.txt")
        let internalFile = appSupport.appendingPathComponent("Needle/index.sqlite-wal")

        try FileManager.default.createDirectory(at: internalFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("visible".utf8).write(to: rootFile)
        try Data("internal".utf8).write(to: internalFile)

        let model = SearchAppModel(databaseURL: databaseURL, preferences: AppPreferences(defaults: defaults))
        model.settings = IndexSettings(roots: [directory.path], excludedNamePatterns: [], includeHiddenFiles: false)

        await model.start()
        await model.rebuildIndex()

        XCTAssertFalse(model.results.contains { $0.path.contains("/Needle/index.sqlite") })
        XCTAssertTrue(model.results.contains { URL(fileURLWithPath: $0.path).standardizedFileURL.path == rootFile.standardizedFileURL.path })

        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testBackgroundUnloadsMemoryIndexAndForegroundReloadsFromSQLite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("report.md")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: fileURL)

        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        let model = SearchAppModel(
            databaseURL: databaseURL,
            preferences: AppPreferences(defaults: defaults),
            backgroundUnloadDelay: .zero
        )
        model.settings = IndexSettings(roots: [directory.path], excludedNamePatterns: [], includeHiddenFiles: false)
        model.queryText = "report"

        await model.start()
        await model.rebuildIndex()

        XCTAssertTrue(model.isMemoryIndexLoaded)
        XCTAssertEqual(model.results.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }, [fileURL.standardizedFileURL.path])
        XCTAssertEqual(model.indexedRecordCount, 1)

        model.enterBackground()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(model.isMemoryIndexLoaded)
        XCTAssertEqual(model.results.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }, [fileURL.standardizedFileURL.path])
        XCTAssertEqual(model.indexedRecordCount, 1)

        await model.enterForeground()

        XCTAssertTrue(model.isMemoryIndexLoaded)
        XCTAssertEqual(model.results.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }, [fileURL.standardizedFileURL.path])

        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testSearchFiltersOutDeletedFileBeforeRescanCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("中国高等教育学位在线验证报告.pdf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: fileURL)

        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        let model = SearchAppModel(databaseURL: databaseURL, preferences: AppPreferences(defaults: defaults))
        model.settings = IndexSettings(roots: [directory.path], excludedNamePatterns: [], includeHiddenFiles: false)
        model.queryText = "中国高等教育学位在线验证报告"

        await model.start()
        await model.rebuildIndex()

        XCTAssertEqual(model.results.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }, [fileURL.standardizedFileURL.path])

        try FileManager.default.removeItem(at: fileURL)
        model.queryText = "中国高等教育学位在线验证报告"
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertTrue(model.results.isEmpty)

        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testDefaultListDoesNotSelfHealIntoEmptyResultsFromMissingVisibleFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let firstFileURL = directory.appendingPathComponent("first.txt")
        let secondFileURL = directory.appendingPathComponent("second.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: firstFileURL)
        try Data("second".utf8).write(to: secondFileURL)

        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        let model = SearchAppModel(databaseURL: databaseURL, preferences: AppPreferences(defaults: defaults))
        model.settings = IndexSettings(roots: [directory.path], excludedNamePatterns: [], includeHiddenFiles: false)

        await model.start()
        await model.rebuildIndex()

        XCTAssertFalse(model.results.isEmpty)

        try FileManager.default.removeItem(at: firstFileURL)
        try FileManager.default.removeItem(at: secondFileURL)
        model.matchPath.toggle()
        model.matchPath.toggle()
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertFalse(model.results.isEmpty)

        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testSearchSkipsRedundantRequestsWhenInputsUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("needle-performance-note.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: fileURL)

        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        let model = SearchAppModel(databaseURL: databaseURL, preferences: AppPreferences(defaults: defaults))
        model.settings = IndexSettings(roots: [directory.path], excludedNamePatterns: [], includeHiddenFiles: false)
        model.queryText = "needle-performance-note"

        await model.start()
        await model.rebuildIndex()
        try await Task.sleep(for: .milliseconds(350))

        let executedBefore = model.executedSearchCount
        XCTAssertGreaterThan(executedBefore, 0)

        model.queryText = "needle-performance-note"
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(model.executedSearchCount, executedBefore)
        XCTAssertGreaterThan(model.skippedSearchCount, 0)

        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    func testStartPrunesSQLiteRecordsExcludedByCurrentSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        let store = SQLiteStore(databaseURL: databaseURL)
        try await store.open()
        try await store.upsert([
            makeRecord(path: "/Users/me/project/App.swift", name: "App.swift", ext: "swift"),
            makeRecord(path: "/Users/me/project/node_modules/pkg/index.js", name: "index.js", ext: "js")
        ])

        let model = SearchAppModel(databaseURL: databaseURL, preferences: AppPreferences(defaults: defaults))
        model.settings = IndexSettings(roots: ["/Users/me"], excludedNamePatterns: ["node_modules"], includeHiddenFiles: false)

        await model.start()

        XCTAssertEqual(model.indexedRecordCount, 1)
        let persistedPaths = try await store.loadAll().map(\.path)
        XCTAssertEqual(persistedPaths, ["/Users/me/project/App.swift"])

        try? FileManager.default.removeItem(at: directory)
    }

    func testSettingsDefaultToNoRootsForSafeFirstLaunch() {
        let settings = IndexSettings()

        XCTAssertTrue(settings.roots.isEmpty)
    }

    func testSettingsDefaultToCommonExclusions() {
        let settings = IndexSettings()

        XCTAssertEqual(settings.excludedNamePatterns, IndexSettings.commonExcludedNamePatterns)
        XCTAssertEqual(
            settings.excludedNamePatterns,
            [
                ".DS_Store",
                "Library/Caches",
                "Library/HTTPStorages",
                "Safari/Favicon Cache",
                ".Trash",
                "node_modules",
                ".build"
            ]
        )
        XCTAssertFalse(settings.shouldIndex(path: "/Users/me/Library/Caches/cache.db", name: "cache.db"))
        XCTAssertFalse(settings.shouldIndex(path: "/Users/me/Library/HTTPStorages/site.sqlite", name: "site.sqlite"))
        XCTAssertFalse(settings.shouldIndex(path: "/Users/me/Library/Safari/Favicon Cache/favicon.db", name: "favicon.db"))
        XCTAssertFalse(settings.shouldIndex(path: "/Users/me/Library/Containers/com.app/Data/Library/Caches/cache.db", name: "cache.db"))
        XCTAssertFalse(settings.shouldIndex(path: "/Users/me/.Trash/old.txt", name: "old.txt"))
        XCTAssertFalse(settings.shouldIndex(path: "/Users/me/project/node_modules/pkg/index.js", name: "index.js"))
        XCTAssertFalse(settings.shouldIndex(path: "/Users/me/project/.build/debug/Needle", name: "Needle"))
        XCTAssertTrue(settings.shouldIndex(path: "/Users/me/Library/Preferences/com.example.app.plist", name: "com.example.app.plist"))
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

    func testAppSettingsDecodeLegacyPayloadKeepsAutoCheckUpdatesEnabledByDefault() throws {
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

        XCTAssertTrue(settings.autoCheckUpdates)
    }

    func testIndexSettingsMigrationKeepsLegacyExclusionsUnchanged() throws {
        let legacyPayload = """
        {
          "roots": ["/Users/me"],
          "excludedPaths": [],
          "excludedNamePatterns": [".git", "node_modules", ".build", "Library/Caches", "DerivedData", ".swiftpm", ".DS_Store"],
          "includeHiddenFiles": false,
          "matchPathByDefault": true
        }
        """.data(using: .utf8)!
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        defaults.set(legacyPayload, forKey: "Needle.IndexSettings")

        let settings = AppPreferences(defaults: defaults).load()

        XCTAssertEqual(
            settings.excludedNamePatterns,
            [".git", "node_modules", ".build", "Library/Caches", "DerivedData", ".swiftpm", ".DS_Store"]
        )
    }

    func testIndexSettingsMigrationUpgradesOldSingleDefaultExclusion() throws {
        let legacyPayload = """
        {
          "roots": ["/Users/me"],
          "excludedPaths": [],
          "excludedNamePatterns": [".DS_Store"],
          "includeHiddenFiles": false,
          "matchPathByDefault": true
        }
        """.data(using: .utf8)!
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        defaults.set(legacyPayload, forKey: "Needle.IndexSettings")

        let preferences = AppPreferences(defaults: defaults)
        let settings = preferences.load()
        let persisted = try XCTUnwrap(defaults.data(forKey: "Needle.IndexSettings"))
        let persistedSettings = try JSONDecoder().decode(IndexSettings.self, from: persisted)

        XCTAssertEqual(settings.excludedNamePatterns, IndexSettings.commonExcludedNamePatterns)
        XCTAssertEqual(persistedSettings.excludedNamePatterns, IndexSettings.commonExcludedNamePatterns)
    }

    func testIndexSettingsMigrationRestoresEmptyExclusionsAndPersistsThem() throws {
        let legacyPayload = """
        {
          "roots": ["/Users/me"],
          "excludedPaths": [],
          "excludedNamePatterns": [],
          "includeHiddenFiles": false,
          "matchPathByDefault": true
        }
        """.data(using: .utf8)!
        let defaults = UserDefaults(suiteName: "NeedleTests.\(UUID().uuidString)")!
        defaults.set(legacyPayload, forKey: "Needle.IndexSettings")

        let preferences = AppPreferences(defaults: defaults)
        let settings = preferences.load()
        let persisted = try XCTUnwrap(defaults.data(forKey: "Needle.IndexSettings"))
        let persistedSettings = try JSONDecoder().decode(IndexSettings.self, from: persisted)

        XCTAssertEqual(settings.excludedNamePatterns, IndexSettings.commonExcludedNamePatterns)
        XCTAssertEqual(persistedSettings.excludedNamePatterns, IndexSettings.commonExcludedNamePatterns)
    }

    func testSettingsExcludeHiddenAndConfiguredNames() {
        let settings = IndexSettings(excludedNamePatterns: [".git", "node_modules"])

        XCTAssertFalse(settings.shouldIndex(path: "/tmp/.env", name: ".env"))
        XCTAssertFalse(settings.shouldIndex(path: "/tmp/project/node_modules/pkg", name: "pkg"))
        XCTAssertTrue(settings.shouldIndex(path: "/tmp/project/Sources/App.swift", name: "App.swift"))
    }

    func testSettingsDoesNotExcludeOmxStateDirectoriesByDefault() {
        let settings = IndexSettings()

        XCTAssertTrue(settings.shouldIndex(path: "/Users/me/Desktop/.omx/logs/turns.jsonl", name: "turns.jsonl"))
        XCTAssertTrue(settings.shouldIndex(path: "/Users/me/.codex/logs_2.sqlite", name: "logs_2.sqlite"))
        XCTAssertTrue(settings.shouldIndex(path: "/Users/me/Library/Logs/codex-plusplus-watcher.log", name: "codex-plusplus-watcher.log"))
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

    func testMergedRecordsReplacesOnlyChangedSubtreesAndPreservesOpenStats() {
        let records = [
            makeRecord(path: "/Users/me/Downloads", name: "Downloads", kind: .folder, ext: "", openCount: 2),
            makeRecord(path: "/Users/me/Downloads/old.dmg", name: "old.dmg", ext: "dmg", openCount: 4),
            makeRecord(path: "/Users/me/Documents/keep.md", name: "keep.md", ext: "md", openCount: 1),
            makeRecord(path: "/Users/me/Downloads sibling/keep.txt", name: "keep.txt")
        ]
        let newRecords = [
            makeRecord(path: "/Users/me/Downloads/new.dmg", name: "new.dmg", ext: "dmg"),
            makeRecord(path: "/Users/me/Downloads/old.dmg", name: "old.dmg", ext: "dmg")
        ]

        let merged = SearchAppModel.mergedRecords(records, newRecords: newRecords, replacing: ["/Users/me/Downloads"])
        let paths = Set(merged.map(\.path))

        XCTAssertFalse(paths.contains("/Users/me/Downloads"))
        XCTAssertTrue(paths.contains("/Users/me/Downloads/new.dmg"))
        XCTAssertTrue(paths.contains("/Users/me/Documents/keep.md"))
        XCTAssertTrue(paths.contains("/Users/me/Downloads sibling/keep.txt"))
        XCTAssertEqual(merged.first { $0.path == "/Users/me/Downloads/old.dmg" }?.openCount, 4)
    }

    func testMergedRecordsTreatsFileEventsAsExactReplacements() {
        let records = [
            makeRecord(path: "/Users/me/Downloads", name: "Downloads", kind: .folder, ext: ""),
            makeRecord(path: "/Users/me/Downloads/app.dmg", name: "app.dmg", ext: "dmg", openCount: 3),
            makeRecord(path: "/Users/me/Downloads/app.dmg.meta", name: "app.dmg.meta", ext: "meta")
        ]
        let newRecords = [
            makeRecord(path: "/Users/me/Downloads/app.dmg", name: "app.dmg", ext: "dmg")
        ]

        let merged = SearchAppModel.mergedRecords(records, newRecords: newRecords, replacing: ["/Users/me/Downloads/app.dmg"])
        let paths = Set(merged.map(\.path))

        XCTAssertTrue(paths.contains("/Users/me/Downloads"))
        XCTAssertTrue(paths.contains("/Users/me/Downloads/app.dmg"))
        XCTAssertTrue(paths.contains("/Users/me/Downloads/app.dmg.meta"))
        XCTAssertEqual(merged.first { $0.path == "/Users/me/Downloads/app.dmg" }?.openCount, 3)
    }

    func testShouldReplaceUsesPathAncestorsInsteadOfPrefixSiblingMatches() {
        let roots: Set<String> = ["/Users/me/Downloads"]

        XCTAssertTrue(SearchAppModel.shouldReplace("/Users/me/Downloads", roots: roots))
        XCTAssertTrue(SearchAppModel.shouldReplace("/Users/me/Downloads/PlayCover.dmg", roots: roots))
        XCTAssertFalse(SearchAppModel.shouldReplace("/Users/me/Downloads sibling/keep.txt", roots: roots))
    }

    func testCompactedRescanPathsRemovesChildrenCoveredByParents() {
        let compacted = SearchAppModel.compactedRescanPaths(
            [
                "/Users/me/Downloads",
                "/Users/me/Downloads/PlayCover.dmg",
                "/Users/me/Downloads/Nested/file.txt",
                "/Users/me/Documents/report.md"
            ],
            indexedRoots: ["/Users/me"],
            maxPaths: 512
        )

        XCTAssertEqual(compacted, ["/Users/me/Documents/report.md", "/Users/me/Downloads"])
    }

    func testCompactedRescanPathsPromotesEventStormsToIndexedRootChildren() {
        let paths = (0..<700).map { "/Users/me/Downloads/build/file-\($0).tmp" }
            + (0..<700).map { "/Users/me/Library/Caches/cache-\($0).db" }

        let compacted = SearchAppModel.compactedRescanPaths(
            paths,
            indexedRoots: ["/Users/me"],
            maxPaths: 128
        )

        XCTAssertEqual(compacted, ["/Users/me/Downloads", "/Users/me/Library"])
    }

    func testPreparedRescanPathsDropsInternalExcludedAndIndexedRootEvents() {
        let settings = IndexSettings(
            roots: ["/Users/me"],
            excludedNamePatterns: [".omx"],
            includeHiddenFiles: true
        )

        let prepared = SearchAppModel.preparedRescanPaths(
            [
                "/Users/me",
                "/Users/me/.omx/state.json",
                "/Users/me/Library/Application Support/Needle/index.sqlite-wal",
                "/Users/me/Downloads/PlayCover.dmg"
            ],
            settings: settings,
            internalExcludedRoots: ["/Users/me/Library/Application Support/Needle"],
            maxPaths: 512
        )

        XCTAssertEqual(prepared, ["/Users/me/Downloads/PlayCover.dmg"])
    }

    func testProtectedAppDataPathDetection() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        XCTAssertTrue(SearchAppModel.isProtectedAppDataPath("\(home)/Library/Application Support/Quark/data.db"))
        XCTAssertTrue(SearchAppModel.isProtectedAppDataPath("\(home)/Library/Containers/com.apple.mail"))
        XCTAssertFalse(SearchAppModel.isProtectedAppDataPath("\(home)/Downloads/report.pdf"))
    }

    func testNormalizedVersionStringStripsLeadingV() {
        XCTAssertEqual(SearchAppModel.normalizedVersionString("v0.2.4"), "0.2.4")
        XCTAssertEqual(SearchAppModel.normalizedVersionString("0.2.4"), "0.2.4")
    }

    func testCompareVersionUsesSemanticSegments() {
        XCTAssertEqual(SearchAppModel.compareVersion("v0.2.10", "0.2.9"), .orderedDescending)
        XCTAssertEqual(SearchAppModel.compareVersion("0.2.3", "0.2.3"), .orderedSame)
        XCTAssertEqual(SearchAppModel.compareVersion("0.2.2", "0.2.3"), .orderedAscending)
    }

    func testBackgroundEventBufferAggregatesEventsOffMainActor() {
        let buffer = BackgroundEventBuffer(pathLimit: 3)

        XCTAssertFalse(buffer.enqueueIfBackground(FSEventsUpdate(paths: ["/tmp/a"], requiresFullRescan: false, reason: nil)))

        buffer.enterBackground()

        XCTAssertTrue(buffer.enqueueIfBackground(FSEventsUpdate(paths: ["/tmp/a"], requiresFullRescan: false, reason: nil)))
        XCTAssertTrue(buffer.enqueueIfBackground(FSEventsUpdate(paths: ["/tmp/b", "/tmp/c"], requiresFullRescan: false, reason: nil)))

        let drained = buffer.drainAndEnterForeground()
        XCTAssertEqual(Set(drained?.paths ?? []), ["/tmp/a", "/tmp/b", "/tmp/c"])
        XCTAssertEqual(drained?.requiresFullRescan, false)
        XCTAssertFalse(buffer.enqueueIfBackground(FSEventsUpdate(paths: ["/tmp/d"], requiresFullRescan: false, reason: nil)))
    }

    func testBackgroundEventBufferPromotesOverflowToForegroundFullRescan() {
        let buffer = BackgroundEventBuffer(pathLimit: 1)

        buffer.enterBackground()
        XCTAssertTrue(buffer.enqueueIfBackground(FSEventsUpdate(paths: ["/tmp/a", "/tmp/b"], requiresFullRescan: false, reason: nil)))

        let drained = buffer.drainAndEnterForeground()
        XCTAssertEqual(drained?.paths, [])
        XCTAssertEqual(drained?.requiresFullRescan, true)
        XCTAssertEqual(drained?.reason, "后台文件系统事件过多")
    }

    func testMergedRecordsHandlesLargeEventBatchesQuickly() {
        let records = (0..<30_000).map { index in
            makeRecord(
                path: "/Users/me/Project\(index % 200)/Nested\(index % 50)/file-\(index).swift",
                name: "file-\(index).swift",
                ext: "swift",
                openCount: index % 3
            )
        }
        let replacing = (0..<400).map { "/Users/me/Project\($0 % 200)/Nested\($0 % 50)" }
        let newRecords = (0..<400).map { index in
            makeRecord(
                path: "/Users/me/Project\(index % 200)/Nested\(index % 50)/new-\(index).swift",
                name: "new-\(index).swift",
                ext: "swift"
            )
        }

        measure {
            _ = SearchAppModel.mergedRecords(records, newRecords: newRecords, replacing: replacing)
        }
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

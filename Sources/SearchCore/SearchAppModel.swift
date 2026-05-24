import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class SearchAppModel {
    public private(set) var records: [FileRecord] = []
    public private(set) var results: [FileRecord] = []
    public private(set) var state: IndexerState = .idle
    public private(set) var lastError: String?
    public private(set) var blockedPaths: [String] = []
    public private(set) var missingIndexedRoots: [String] = []
    public private(set) var permissionStatus = PermissionStatus()
    public private(set) var queryWarning: String?
    public private(set) var indexedSettings: IndexSettings?
    public private(set) var lastSearchDurationMS: Double?
    public private(set) var lastRebuildDurationMS: Double?
    public private(set) var lastRescanDurationMS: Double?
    public private(set) var lastFSEventBatchCount: Int?

    public var queryText: String = "" {
        didSet { scheduleSearch() }
    }
    public var kindFilter: KindFilter = .all {
        didSet { scheduleSearch() }
    }
    public var matchPath = true {
        didSet { scheduleSearch() }
    }
    public var settings: IndexSettings {
        didSet {
            preferences.save(settings)
            matchPath = settings.matchPathByDefault
        }
    }
    public var appSettings: AppSettings {
        didSet {
            preferences.save(appSettings)
        }
    }

    public var indexNeedsRebuild: Bool {
        guard !settings.roots.isEmpty else { return false }
        guard let indexedSettings else { return true }
        return !settings.hasSameIndexScope(as: indexedSettings)
    }

    private let store: SQLiteStore
    private let indexer: FileIndexer
    private let searchEngine = SearchEngine()
    private let preferences: AppPreferences
    private let watcher: FSEventsWatcher
    private let modelBox: ModelBox
    private var rescanTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var workspaceObservers: [NSObjectProtocol] = []

    public init(
        databaseURL: URL = SearchAppModel.defaultDatabaseURL(),
        preferences: AppPreferences = AppPreferences()
    ) {
        let modelBox = ModelBox()
        self.store = SQLiteStore(databaseURL: databaseURL)
        self.indexer = FileIndexer()
        self.preferences = preferences
        let loadedSettings = preferences.load()
        let loadedAppSettings = preferences.loadAppSettings()
        self.settings = loadedSettings
        self.appSettings = loadedAppSettings
        self.matchPath = loadedSettings.matchPathByDefault
        self.modelBox = modelBox
        self.watcher = FSEventsWatcher { [weak modelBox] update in
            Task { @MainActor [weak modelBox] in
                guard let model = modelBox?.model else { return }
                model.handleFSEvents(update)
            }
        }
        modelBox.model = self
    }

    public static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("Needle", isDirectory: true)
            .appendingPathComponent("index.sqlite")
    }

    public func start() async {
        refreshPermissionStatus()
        installWorkspaceObservers()
        refreshMissingIndexedRoots()
        state = .loading
        do {
            try await store.open()
            records = try await store.loadAll()
            searchNow()
            startWatching()
            if records.isEmpty && !settings.roots.isEmpty {
                await rebuildIndex()
            } else {
                indexedSettings = settings
                state = settings.roots.isEmpty ? .idle : .watching
            }
        } catch {
            lastError = error.localizedDescription
            state = .degraded(error.localizedDescription)
        }
    }

    public func rebuildIndex() async {
        guard !settings.roots.isEmpty else {
            records = []
            results = []
            state = .idle
            return
        }

        state = .scanning(processed: 0)
        blockedPaths = []
        let currentSettings = settings
        let startedAt = CFAbsoluteTimeGetCurrent()
        refreshMissingIndexedRoots()
        guard missingIndexedRoots.isEmpty else {
            state = .permissionBlocked("索引位置不可用：\(missingIndexedRoots.first ?? "")")
            return
        }
        let result = await indexer.scan(settings: currentSettings) { [weak self] processed in
            await MainActor.run {
                self?.state = .scanning(processed: processed)
            }
        }

        do {
            try await store.replaceAll(with: result.records)
            records = result.records
            blockedPaths = result.blockedPaths
            indexedSettings = currentSettings
            lastRebuildDurationMS = elapsedMilliseconds(since: startedAt)
            searchNow()
            startWatching()
            state = result.blockedPaths.isEmpty ? .watching : .permissionBlocked(result.blockedPaths.first ?? "部分目录无法访问")
        } catch {
            lastError = error.localizedDescription
            state = .degraded(error.localizedDescription)
        }
    }

    public func addRoot(_ url: URL) {
        let path = url.path
        guard !settings.roots.contains(path) else { return }
        settings.roots.append(path)
        refreshMissingIndexedRoots()
    }

    public func removeRoot(_ path: String) {
        settings.roots.removeAll { $0 == path }
        refreshMissingIndexedRoots()
    }

    public func open(_ record: FileRecord) {
        NSWorkspace.shared.open(URL(fileURLWithPath: record.path))
        noteRecordOpened(path: record.path)
        Task {
            try? await store.recordOpen(path: record.path)
        }
    }

    public func openWithApplicationPicker(_ record: FileRecord) {
        let panel = NSOpenPanel()
        panel.title = "选择打开方式"
        panel.prompt = "打开"
        panel.message = "选择一个应用来打开“\(record.name)”。"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let applicationURL = panel.url else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: record.path)],
            withApplicationAt: applicationURL,
            configuration: configuration
        )

        Task {
            try? await store.recordOpen(path: record.path)
        }
        noteRecordOpened(path: record.path)
    }

    public func revealInFinder(_ record: FileRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.path)])
    }

    public func openParentFolder(_ record: FileRecord) {
        NSWorkspace.shared.open(URL(fileURLWithPath: record.parentPath, isDirectory: true))
    }

    public func copyPath(_ record: FileRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.path, forType: .string)
    }

    public func copyName(_ record: FileRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.name, forType: .string)
    }

    public func copyParentPath(_ record: FileRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.parentPath, forType: .string)
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openDiagnosticsFolder() {
        let directory = diagnosticsDirectoryURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    @discardableResult
    public func exportDiagnostics() -> URL? {
        let directory = diagnosticsDirectoryURL
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Needle-Diagnostics-\(diagnosticTimestamp()).txt")
            try diagnosticsReport().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            lastError = error.localizedDescription
            state = .degraded(error.localizedDescription)
            return nil
        }
    }

    public func completeOnboarding() {
        appSettings.hasCompletedOnboarding = true
    }

    public func refreshPermissionStatus() {
        permissionStatus = PermissionStatusProvider.current()
    }

    private func refreshResults() {
        searchNow()
    }

    private func scheduleSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        let records = records
        let query = SearchQuery.parse(queryText, kindFilter: kindFilter, matchPath: matchPath)
        let searchEngine = searchEngine
        let preferredFolderPaths = settings.roots
        queryWarning = query.validationMessage

        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }

            let results = await Task.detached(priority: .userInitiated) {
                let startedAt = CFAbsoluteTimeGetCurrent()
                let results = searchEngine.search(records, query: query, preferredFolderPaths: preferredFolderPaths)
                let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                return (results, duration)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.searchGeneration == generation else { return }
                self.results = results.0
                self.lastSearchDurationMS = results.1
            }
        }
    }

    private func searchNow() {
        searchGeneration += 1
        searchTask?.cancel()
        let query = SearchQuery.parse(queryText, kindFilter: kindFilter, matchPath: matchPath)
        queryWarning = query.validationMessage
        let startedAt = CFAbsoluteTimeGetCurrent()
        results = searchEngine.search(records, query: query, preferredFolderPaths: settings.roots)
        lastSearchDurationMS = elapsedMilliseconds(since: startedAt)
    }

    private func noteRecordOpened(path: String, at date: Date = Date()) {
        updateOpenStats(path: path, at: date, in: &records)
        updateOpenStats(path: path, at: date, in: &results)
        refreshResults()
    }

    private func updateOpenStats(path: String, at date: Date, in records: inout [FileRecord]) {
        guard let index = records.firstIndex(where: { $0.path == path }) else { return }
        records[index].openCount += 1
        records[index].lastOpenedAt = date
    }

    private var diagnosticsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("Needle", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private func diagnosticsReport() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        lines.append("Needle Diagnostics")
        lines.append("Generated: \(formatter.string(from: Date()))")
        lines.append("Records: \(records.count)")
        lines.append("State: \(stateDescription)")
        lines.append("Index needs rebuild: \(indexNeedsRebuild)")
        lines.append("Last search duration ms: \(formattedMetric(lastSearchDurationMS))")
        lines.append("Last rebuild duration ms: \(formattedMetric(lastRebuildDurationMS))")
        lines.append("Last rescan duration ms: \(formattedMetric(lastRescanDurationMS))")
        lines.append("Last FSEvents batch count: \(lastFSEventBatchCount.map(String.init) ?? "-")")
        lines.append("Search query: \(queryText)")
        lines.append("Kind filter: \(kindFilter.rawValue)")
        lines.append("Match path: \(matchPath)")
        lines.append("Roots: \(settings.roots.joined(separator: ", "))")
        lines.append("Missing indexed roots: \(missingIndexedRoots.joined(separator: ", "))")
        lines.append("Excluded paths: \(settings.excludedPaths.joined(separator: ", "))")
        lines.append("Excluded names: \(settings.excludedNamePatterns.joined(separator: ", "))")
        lines.append("Include hidden files: \(settings.includeHiddenFiles)")
        lines.append("Launch at login: \(appSettings.launchAtLogin)")
        lines.append("Global shortcut enabled: \(appSettings.globalShortcutEnabled)")
        lines.append("Keep running after window close: \(appSettings.keepRunningAfterWindowClose)")
        lines.append("Permissions: fullDisk=\(permissionStatus.fullDiskAccessGranted), accessibility=\(permissionStatus.accessibilityGranted)")
        lines.append("Blocked paths: \(blockedPaths.joined(separator: ", "))")
        if let lastError {
            lines.append("Last error: \(lastError)")
        }
        return lines.joined(separator: "\n")
    }

    private func diagnosticTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private var stateDescription: String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .scanning(let processed):
            return "scanning:\(processed)"
        case .watching:
            return "watching"
        case .permissionBlocked(let message):
            return "permissionBlocked:\(message)"
        case .degraded(let message):
            return "degraded:\(message)"
        }
    }

    private func startWatching() {
        refreshMissingIndexedRoots()
        guard missingIndexedRoots.isEmpty else {
            state = .permissionBlocked("索引位置不可用：\(missingIndexedRoots.first ?? "")")
            return
        }

        let didStart = watcher.start(paths: settings.roots)
        if !didStart {
            state = .degraded("文件系统监听启动失败")
        }
    }

    private func installWorkspaceObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        let didMount = center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVolumeAvailabilityChanged()
            }
        }

        let didUnmount = center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleVolumeAvailabilityChanged()
            }
        }

        workspaceObservers = [didMount, didUnmount]
    }

    private func handleVolumeAvailabilityChanged() {
        refreshMissingIndexedRoots()
        if missingIndexedRoots.isEmpty {
            if records.isEmpty, !settings.roots.isEmpty {
                Task { await rebuildIndex() }
            } else {
                startWatching()
                state = settings.roots.isEmpty ? .idle : .watching
            }
        } else {
            watcher.stop()
            state = .permissionBlocked("索引位置不可用：\(missingIndexedRoots.first ?? "")")
        }
    }

    private func refreshMissingIndexedRoots() {
        missingIndexedRoots = settings.roots.filter { !FileManager.default.fileExists(atPath: $0) }
    }

    private func handleFSEvents(_ update: FSEventsUpdate) {
        lastFSEventBatchCount = update.paths.count
        if update.requiresFullRescan {
            lastError = update.reason
            Task { await rebuildIndex() }
        } else if let reason = update.reason {
            lastError = reason
            state = .degraded(reason)
        } else {
            scheduleRescan(paths: update.paths)
        }
    }

    private func scheduleRescan(paths: [String]) {
        lastFSEventBatchCount = paths.count
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.rescan(paths: paths)
        }
    }

    private func rescan(paths: [String]) async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let uniquePaths = Array(Set(paths))
        let currentSettings = settings
        let indexer = indexer
        let newRecords = await withTaskGroup(of: [FileRecord].self) { group in
            for path in uniquePaths {
                group.addTask {
                    await indexer.scanSinglePath(path, settings: currentSettings)
                }
            }
            var collected: [FileRecord] = []
            for await records in group {
                collected.append(contentsOf: records)
            }
            return collected
        }

        do {
            try await store.delete(paths: uniquePaths)
            try await store.upsert(newRecords)
            records = try await store.loadAll()
            lastRescanDurationMS = elapsedMilliseconds(since: startedAt)
            refreshResults()
            state = .watching
        } catch {
            lastError = error.localizedDescription
            state = .degraded(error.localizedDescription)
        }
    }

    private func elapsedMilliseconds(since startedAt: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
    }

    private func formattedMetric(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.2f", value)
    }
}

private final class ModelBox: @unchecked Sendable {
    @MainActor weak var model: SearchAppModel?
}

import AppKit
import Darwin
import Foundation
import Observation

@MainActor
@Observable
public final class SearchAppModel {
    public private(set) var results: [FileRecord] = []
    public private(set) var indexedRecordCount = 0
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
    public private(set) var lastFilteredFSEventBatchCount: Int?
    public private(set) var lastRescanPathSample: [String] = []
    public private(set) var isSearching = false
    public private(set) var isMemoryIndexLoaded = false

    public var queryText: String = "" {
        didSet { scheduleSearch(showActivity: true) }
    }
    public var kindFilter: KindFilter = .all {
        didSet { scheduleSearch(showActivity: true) }
    }
    public var matchPath = true {
        didSet { scheduleSearch(showActivity: true) }
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
    private let backgroundEventBuffer: BackgroundEventBuffer
    private let databaseURL: URL
    private let databaseDirectoryURL: URL
    @ObservationIgnored private var recordsStorage: [FileRecord] = []
    private var rescanTask: Task<Void, Never>?
    private var pendingRescanPaths = Set<String>()
    private var deferredBackgroundEventPaths = Set<String>()
    private var isRescanning = false
    private var isBackgroundRequested = false
    private var needsFullRescanOnForeground = false
    private var needsSearchAfterRescan = false
    private var searchTask: Task<Void, Never>?
    private var searchActivityTask: Task<Void, Never>?
    private var visibilityMonitorTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private let pendingRescanPathLimit = 512
    private let fileManager = FileManager.default

    public init(
        databaseURL: URL = SearchAppModel.defaultDatabaseURL(),
        preferences: AppPreferences = AppPreferences()
    ) {
        let modelBox = ModelBox()
        let backgroundEventBuffer = BackgroundEventBuffer(pathLimit: 512)
        self.databaseURL = databaseURL
        self.store = SQLiteStore(databaseURL: databaseURL)
        self.databaseDirectoryURL = databaseURL.deletingLastPathComponent()
        self.indexer = FileIndexer()
        self.preferences = preferences
        let loadedSettings = preferences.load()
        let loadedAppSettings = preferences.loadAppSettings()
        self.settings = loadedSettings
        self.appSettings = loadedAppSettings
        self.matchPath = loadedSettings.matchPathByDefault
        self.modelBox = modelBox
        self.backgroundEventBuffer = backgroundEventBuffer
        self.watcher = FSEventsWatcher { [weak modelBox, backgroundEventBuffer] update in
            if backgroundEventBuffer.enqueueIfBackground(update) {
                return
            }
            Task { @MainActor [weak modelBox] in
                guard let model = modelBox?.model else { return }
                model.handleFSEvents(update)
            }
        }
        modelBox.model = self
        startVisibilityMonitorIfNeeded()
    }

    public static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("Needle", isDirectory: true)
            .appendingPathComponent("index.sqlite")
    }

    public func start() async {
        if appSettings.hasCompletedOnboarding {
            refreshPermissionStatus()
        }
        installWorkspaceObservers()
        refreshMissingIndexedRoots()
        state = .loading
        do {
            try await store.open()
            let loadedRecords = try await store.loadAll()
            let scopedRecords = filterIndexSettingsRecords(from: loadedRecords)
            if scopedRecords.count != loadedRecords.count {
                try await store.replaceAll(with: scopedRecords)
            }
            recordsStorage = filterPermissionRestrictedRecords(from: scopedRecords)
            isMemoryIndexLoaded = true
            indexedRecordCount = recordsStorage.count
            refreshResults()
            if appSettings.hasCompletedOnboarding {
                startWatching()
                if recordsStorage.isEmpty && !settings.roots.isEmpty {
                    await rebuildIndex()
                } else {
                    indexedSettings = settings
                    state = settings.roots.isEmpty ? .idle : .watching
                }
            } else {
                indexedSettings = settings
                state = .idle
            }
        } catch {
            lastError = error.localizedDescription
            state = .degraded(error.localizedDescription)
        }
    }

    public func rebuildIndex() async {
        guard !settings.roots.isEmpty else {
            recordsStorage = []
            isMemoryIndexLoaded = true
            indexedRecordCount = 0
            results = []
            stopSearchActivity()
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
        let filteredRecords = filterInternalRecords(from: result.records)

        do {
            try await store.replaceAll(with: filteredRecords)
            recordsStorage = filterPermissionRestrictedRecords(from: filteredRecords)
            isMemoryIndexLoaded = true
            indexedRecordCount = filteredRecords.count
            blockedPaths = result.blockedPaths
            indexedSettings = currentSettings
            lastRebuildDurationMS = elapsedMilliseconds(since: startedAt)
            await refreshResultsImmediately()
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
        refreshPermissionStatus()
        Task { [weak self] in
            await self?.resumeIndexingAfterOnboarding()
        }
    }

    public func refreshPermissionStatus() {
        let previous = permissionStatus
        permissionStatus = PermissionStatusProvider.current()
        guard previous != permissionStatus else { return }
        handlePermissionStatusChanged(previous: previous, current: permissionStatus)
    }

    public func enterBackground() {
        backgroundEventBuffer.enterBackground()
        if isBackgroundRequested, !hasForegroundResources, !hasActiveForegroundWork {
            return
        }

        isBackgroundRequested = true
        guard state != .loading else { return }
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        rescanTask?.cancel()
        rescanTask = nil
        stopSearchActivity()

        needsSearchAfterRescan = false
        unloadMemoryIndex()
    }

    public func enterForeground() async {
        if let update = backgroundEventBuffer.drainAndEnterForeground() {
            queueRawBackgroundEvents(update)
        }
        isBackgroundRequested = false
        materializeDeferredBackgroundEvents()
        guard !isMemoryIndexLoaded else {
            if needsFullRescanOnForeground {
                needsFullRescanOnForeground = false
                await rebuildIndex()
            } else if !pendingRescanPaths.isEmpty {
                await runPendingRescan()
            }
            return
        }

        state = .loading
        do {
            if needsFullRescanOnForeground {
                needsFullRescanOnForeground = false
                isMemoryIndexLoaded = true
                await rebuildIndex()
                return
            }

            recordsStorage = try await store.loadAll()
            recordsStorage = filterPermissionRestrictedRecords(from: recordsStorage)
            indexedRecordCount = recordsStorage.count
            isMemoryIndexLoaded = true
            indexedSettings = settings
            startWatching()
            if !pendingRescanPaths.isEmpty {
                await runPendingRescan()
            } else {
                await refreshResultsImmediately()
                state = settings.roots.isEmpty ? .idle : .watching
            }
        } catch {
            lastError = error.localizedDescription
            state = .degraded(error.localizedDescription)
        }
    }

    private func refreshResults(showActivity: Bool = false) {
        scheduleSearch(delay: .milliseconds(0), showActivity: showActivity)
    }

    private func startVisibilityMonitorIfNeeded() {
        guard visibilityMonitorTask == nil else { return }
        visibilityMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await MainActor.run {
                    guard let self else { return }
                    let hasVisibleWindow = NSApplication.shared.activationPolicy() == .regular
                        && NSApplication.shared.windows.contains { window in
                        window.identifier?.rawValue == "NeedleSearchWindow"
                            && window.isVisible
                            && !window.isMiniaturized
                            && window.occlusionState.contains(.visible)
                    }
                    if hasVisibleWindow {
                        Task { await self.enterForeground() }
                    } else {
                        self.enterBackground()
                    }
                }
            }
        }
    }

    private func refreshResultsImmediately() async {
        searchGeneration += 1
        let generation = searchGeneration
        guard isMemoryIndexLoaded else { return }
        let records = recordsStorage
        let query = SearchQuery.parse(queryText, kindFilter: kindFilter, matchPath: matchPath)
        let searchEngine = searchEngine
        let preferredFolderPaths = settings.roots
        queryWarning = query.validationMessage

        searchTask?.cancel()
        stopSearchActivity()

        let startedAt = CFAbsoluteTimeGetCurrent()
        let newResults = await Task.detached(priority: .userInitiated) {
            searchEngine.search(records, query: query, preferredFolderPaths: preferredFolderPaths)
        }.value

        guard searchGeneration == generation else { return }
        applyVisibleResultsAndQueueSelfHeal(newResults)
        lastSearchDurationMS = elapsedMilliseconds(since: startedAt)
        stopSearchActivity()
    }

    private func scheduleSearch(showActivity: Bool) {
        scheduleSearch(delay: .milliseconds(80), showActivity: showActivity)
    }

    private func scheduleSearch(delay: Duration, showActivity: Bool) {
        searchGeneration += 1
        let generation = searchGeneration
        guard isMemoryIndexLoaded else { return }
        let records = recordsStorage
        let query = SearchQuery.parse(queryText, kindFilter: kindFilter, matchPath: matchPath)
        let searchEngine = searchEngine
        let preferredFolderPaths = settings.roots
        queryWarning = query.validationMessage

        searchTask?.cancel()
        if showActivity {
            beginSearchActivityIfSlow(generation: generation)
        } else {
            stopSearchActivity()
        }
        guard !isRescanning else {
            needsSearchAfterRescan = true
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }

            let searchJob = Task.detached(priority: .userInitiated) {
                let startedAt = CFAbsoluteTimeGetCurrent()
                let results = searchEngine.search(records, query: query, preferredFolderPaths: preferredFolderPaths)
                let duration = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                return (results, duration)
            }

            let results = await withTaskCancellationHandler {
                await searchJob.value
            } onCancel: {
                searchJob.cancel()
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.searchGeneration == generation else { return }
                self.applyVisibleResultsAndQueueSelfHeal(results.0)
                self.lastSearchDurationMS = results.1
                self.stopSearchActivity()
            }
        }
    }

    private func beginSearchActivityIfSlow(generation: Int) {
        searchActivityTask?.cancel()
        isSearching = false
        guard !recordsStorage.isEmpty else { return }

        searchActivityTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.searchGeneration == generation else { return }
                self.isSearching = true
            }
        }
    }

    private func stopSearchActivity() {
        searchActivityTask?.cancel()
        searchActivityTask = nil
        isSearching = false
    }

    private func applyVisibleResultsAndQueueSelfHeal(_ candidates: [FileRecord]) {
        guard !candidates.isEmpty else {
            results = []
            return
        }

        var visible: [FileRecord] = []
        visible.reserveCapacity(candidates.count)
        var missingPaths = Set<String>()

        for record in candidates {
            if fileManager.fileExists(atPath: record.path) {
                visible.append(record)
            } else {
                missingPaths.insert(record.path)
            }
        }

        results = visible
        guard !missingPaths.isEmpty else { return }

        recordsStorage.removeAll { missingPaths.contains($0.path) }
        indexedRecordCount = recordsStorage.count
        pendingRescanPaths.formUnion(missingPaths)
        schedulePendingRescanTask()
    }

    private func noteRecordOpened(path: String, at date: Date = Date()) {
        updateOpenStats(path: path, at: date, in: &recordsStorage)
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
        lines.append("Records: \(indexedRecordCount)")
        lines.append("Memory index loaded: \(isMemoryIndexLoaded)")
        lines.append("Visible results: \(results.count)")
        lines.append("State: \(stateDescription)")
        lines.append("Index needs rebuild: \(indexNeedsRebuild)")
        lines.append("Last search duration ms: \(formattedMetric(lastSearchDurationMS))")
        lines.append("Last rebuild duration ms: \(formattedMetric(lastRebuildDurationMS))")
        lines.append("Last rescan duration ms: \(formattedMetric(lastRescanDurationMS))")
        lines.append("Last FSEvents batch count: \(lastFSEventBatchCount.map(String.init) ?? "-")")
        lines.append("Last filtered FSEvents batch count: \(lastFilteredFSEventBatchCount.map(String.init) ?? "-")")
        lines.append("Last rescan path sample: \(lastRescanPathSample.joined(separator: ", "))")
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
            if recordsStorage.isEmpty, !settings.roots.isEmpty {
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

    private func resumeIndexingAfterOnboarding() async {
        guard appSettings.hasCompletedOnboarding else { return }
        refreshMissingIndexedRoots()
        if settings.roots.isEmpty {
            state = .idle
            return
        }

        startWatching()
        if recordsStorage.isEmpty {
            await rebuildIndex()
        } else {
            indexedSettings = settings
            state = .watching
        }
    }

    private func handleFSEvents(_ update: FSEventsUpdate) {
        if isBackgroundRequested || !isMemoryIndexLoaded {
            queueRawBackgroundEvents(update)
            return
        }

        lastFSEventBatchCount = update.paths.count
        let filteredPaths = filterInternalPaths(update.paths)
        lastFilteredFSEventBatchCount = filteredPaths.count
        guard !filteredPaths.isEmpty || update.requiresFullRescan else { return }
        if update.requiresFullRescan {
            lastError = update.reason
            Task { await rebuildIndex() }
        } else if let reason = update.reason {
            lastError = reason
            state = .degraded(reason)
        } else {
            scheduleRescan(paths: filteredPaths)
        }
    }

    private func queueRawBackgroundEvents(_ update: FSEventsUpdate) {
        lastFSEventBatchCount = update.paths.count
        lastFilteredFSEventBatchCount = nil
        lastRescanPathSample = Array(update.paths.prefix(8))
        if update.requiresFullRescan {
            needsFullRescanOnForeground = true
            lastError = update.reason
            deferredBackgroundEventPaths.removeAll()
            return
        }

        let availableCapacity = max(0, pendingRescanPathLimit - deferredBackgroundEventPaths.count)
        guard update.paths.count <= availableCapacity else {
            needsFullRescanOnForeground = true
            deferredBackgroundEventPaths.removeAll()
            return
        }

        deferredBackgroundEventPaths.formUnion(update.paths)
    }

    private func materializeDeferredBackgroundEvents() {
        guard !deferredBackgroundEventPaths.isEmpty else { return }
        let paths = Array(deferredBackgroundEventPaths)
        deferredBackgroundEventPaths.removeAll()
        queueBackgroundRescan(paths: paths)
    }

    private func queueBackgroundRescan(paths: [String]) {
        let compactedPaths = Self.preparedRescanPaths(
            paths,
            settings: settings,
            internalExcludedRoots: internalExcludedRoots,
            maxPaths: pendingRescanPathLimit
        )
        lastFilteredFSEventBatchCount = compactedPaths.count
        lastRescanPathSample = Array(compactedPaths.prefix(8))
        guard !compactedPaths.isEmpty else { return }

        let mergedPendingPaths = Array(pendingRescanPaths) + compactedPaths
        pendingRescanPaths = Set(Self.preparedRescanPaths(
            mergedPendingPaths,
            settings: settings,
            internalExcludedRoots: internalExcludedRoots,
            maxPaths: pendingRescanPathLimit
        ))
    }

    private func scheduleRescan(paths: [String]) {
        let compactedPaths = Self.preparedRescanPaths(
            paths,
            settings: settings,
            internalExcludedRoots: internalExcludedRoots,
            maxPaths: pendingRescanPathLimit
        )
        lastFilteredFSEventBatchCount = compactedPaths.count
        lastRescanPathSample = Array(compactedPaths.prefix(8))
        #if DEBUG
        writeLastRescanSnapshot(paths: compactedPaths)
        #endif
        guard !compactedPaths.isEmpty else { return }
        let mergedPendingPaths = Array(pendingRescanPaths) + compactedPaths
        pendingRescanPaths = Set(Self.preparedRescanPaths(
            mergedPendingPaths,
            settings: settings,
            internalExcludedRoots: internalExcludedRoots,
            maxPaths: pendingRescanPathLimit
        ))
        schedulePendingRescanTask()
    }

    private func schedulePendingRescanTask() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.runPendingRescan()
        }
    }

    private func runPendingRescan() async {
        guard !Task.isCancelled else { return }
        guard !isRescanning else { return }
        guard !pendingRescanPaths.isEmpty else { return }

        let paths = Self.preparedRescanPaths(
            Array(pendingRescanPaths),
            settings: settings,
            internalExcludedRoots: internalExcludedRoots,
            maxPaths: pendingRescanPathLimit
        )
        pendingRescanPaths.removeAll()
        guard !paths.isEmpty else { return }

        isRescanning = true
        await rescan(paths: paths)
        isRescanning = false
        if isBackgroundRequested {
            unloadMemoryIndex()
            return
        }

        if !pendingRescanPaths.isEmpty {
            schedulePendingRescanTask()
        } else if needsSearchAfterRescan {
            needsSearchAfterRescan = false
            refreshResults(showActivity: false)
        }
    }

    private func rescan(paths: [String]) async {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let uniquePaths = Self.preparedRescanPaths(
            paths,
            settings: settings,
            internalExcludedRoots: internalExcludedRoots,
            maxPaths: pendingRescanPathLimit
        )
        guard !uniquePaths.isEmpty else { return }
        guard !Task.isCancelled, !isBackgroundRequested else {
            pendingRescanPaths.formUnion(uniquePaths)
            unloadMemoryIndex()
            return
        }

        let currentSettings = settings
        let indexer = indexer
        let scannedRecords = await withTaskGroup(of: [FileRecord].self) { group in
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
        guard !Task.isCancelled, !isBackgroundRequested else {
            pendingRescanPaths.formUnion(uniquePaths)
            unloadMemoryIndex()
            return
        }
        let newRecords = Self.deduplicatedRecords(filterInternalRecords(from: scannedRecords))
        let visibleNewRecords = filterPermissionRestrictedRecords(from: newRecords)

        do {
            try await store.replaceSubtrees(paths: uniquePaths, with: newRecords)
            guard isMemoryIndexLoaded, !isBackgroundRequested else {
                lastRescanDurationMS = elapsedMilliseconds(since: startedAt)
                unloadMemoryIndex()
                state = .watching
                return
            }
            let currentRecords = recordsStorage
            let mergeJob = Task.detached(priority: .utility) {
                Self.recordsByApplyingRescan(currentRecords, newRecords: visibleNewRecords, replacing: uniquePaths)
            }
            let mergedRecords = await withTaskCancellationHandler {
                await mergeJob.value
            } onCancel: {
                mergeJob.cancel()
            }

            guard !Task.isCancelled, !isBackgroundRequested else {
                pendingRescanPaths.formUnion(uniquePaths)
                unloadMemoryIndex()
                state = .watching
                return
            }

            recordsStorage = mergedRecords
            indexedRecordCount = mergedRecords.count
            lastRescanDurationMS = elapsedMilliseconds(since: startedAt)
            refreshResults(showActivity: false)
            state = .watching
        } catch {
            lastError = error.localizedDescription
            state = .degraded(error.localizedDescription)
        }
    }

    private func unloadMemoryIndex() {
        let hadLoadedResources = hasForegroundResources
        recordsStorage = []
        results = []
        isMemoryIndexLoaded = false
        if hadLoadedResources {
            malloc_zone_pressure_relief(nil, 0)
            NotificationCenter.default.post(name: .needleDidUnloadForegroundResources, object: nil)
        }
    }

    private var hasForegroundResources: Bool {
        isMemoryIndexLoaded || !recordsStorage.isEmpty || !results.isEmpty
    }

    private var hasActiveForegroundWork: Bool {
        searchTask != nil || searchActivityTask != nil || rescanTask != nil || isRescanning
    }

    nonisolated private static func recordsByApplyingRescan(
        _ records: [FileRecord],
        newRecords: [FileRecord],
        replacing paths: [String]
    ) -> [FileRecord] {
        let replacementModes = replacementModes(for: paths, existingRecords: records, newRecords: newRecords)
        guard !Task.isCancelled else { return records }
        guard replacementModes.subtreeRoots.isEmpty else {
            return mergedRecords(records, newRecords: newRecords, replacing: paths)
        }

        return recordsByApplyingExactRescan(
            records,
            newRecords: newRecords,
            exactPaths: replacementModes.exactPaths
        )
    }

    nonisolated private static func recordsByApplyingExactRescan(
        _ records: [FileRecord],
        newRecords: [FileRecord],
        exactPaths: Set<String>
    ) -> [FileRecord] {
        guard !exactPaths.isEmpty else { return records }

        let newRecordsByPath = Dictionary(uniqueKeysWithValues: newRecords.map { ($0.path, $0) })
        let indexByExactPath = indexByPath(for: exactPaths, in: records)
        var changedRecords = records
        var removedIndices: [Int] = []

        for path in exactPaths {
            if Task.isCancelled { return records }

            if var newRecord = newRecordsByPath[path] {
                if let index = indexByExactPath[path] {
                    newRecord.openCount = records[index].openCount
                    newRecord.lastOpenedAt = records[index].lastOpenedAt
                    changedRecords[index] = newRecord
                } else {
                    changedRecords.append(newRecord)
                }
            } else if let index = indexByExactPath[path] {
                removedIndices.append(index)
            }
        }

        for index in removedIndices.sorted(by: >) {
            changedRecords.remove(at: index)
        }

        return changedRecords
    }

    nonisolated private static func indexByPath(for paths: Set<String>, in records: [FileRecord]) -> [String: Int] {
        guard !paths.isEmpty else { return [:] }
        var indexByPath: [String: Int] = [:]
        indexByPath.reserveCapacity(paths.count)
        for (index, record) in records.enumerated() where paths.contains(record.path) {
            if Task.isCancelled { return [:] }

            indexByPath[record.path] = index
            if indexByPath.count == paths.count {
                break
            }
        }
        return indexByPath
    }

    nonisolated static func mergedRecords(
        _ records: [FileRecord],
        newRecords: [FileRecord],
        replacing paths: [String]
    ) -> [FileRecord] {
        var openStatsByPath: [String: (openCount: Int, lastOpenedAt: Date?)] = [:]
        openStatsByPath.reserveCapacity(records.count)

        for record in records {
            if Task.isCancelled { return records }

            let existing = openStatsByPath[record.path]
            openStatsByPath[record.path] = (
                openCount: max(existing?.openCount ?? 0, record.openCount),
                lastOpenedAt: latestDate(existing?.lastOpenedAt, record.lastOpenedAt)
            )
        }

        let replacementModes = replacementModes(for: paths, existingRecords: records, newRecords: newRecords)
        guard !Task.isCancelled else { return records }
        var mergedRecords: [FileRecord] = []
        mergedRecords.reserveCapacity(max(records.count, records.count - paths.count + newRecords.count))

        for record in records {
            if Task.isCancelled { return records }

            guard !replacementModes.exactPaths.contains(record.path) else {
                continue
            }
            guard !shouldReplace(record.path, roots: replacementModes.subtreeRoots) else {
                continue
            }
            mergedRecords.append(record)
        }

        let recordsWithPreservedOpenStats = newRecords.map { record in
            var record = record
            if let stats = openStatsByPath[record.path] {
                record.openCount = stats.openCount
                record.lastOpenedAt = stats.lastOpenedAt
            }
            return record
        }

        mergedRecords.append(contentsOf: recordsWithPreservedOpenStats)
        return mergedRecords
    }

    nonisolated private static func replacementModes(
        for paths: [String],
        existingRecords: [FileRecord],
        newRecords: [FileRecord]
    ) -> (exactPaths: Set<String>, subtreeRoots: Set<String>) {
        let replacementPaths = Set(paths)
        guard !replacementPaths.isEmpty else { return ([], []) }

        var knownFolderPaths = Set(newRecords.lazy.filter { $0.kind == .folder }.map(\.path))
        let knownNewRecordPaths = Set(newRecords.lazy.map(\.path))
        let unresolvedPaths = replacementPaths.subtracting(knownNewRecordPaths)

        if !unresolvedPaths.isEmpty {
            var foundUnresolvedPaths = Set<String>()
            for record in existingRecords where unresolvedPaths.contains(record.path) {
                foundUnresolvedPaths.insert(record.path)
                if record.kind == .folder {
                    knownFolderPaths.insert(record.path)
                }
                if foundUnresolvedPaths.count == unresolvedPaths.count {
                    break
                }
            }
        }

        var exactPaths = Set<String>()
        var subtreeRoots = Set<String>()
        for path in replacementPaths {
            if knownFolderPaths.contains(path) {
                subtreeRoots.insert(path)
            } else {
                exactPaths.insert(path)
            }
        }

        return (exactPaths, subtreeRoots)
    }

    nonisolated static func shouldReplace(
        _ path: String,
        roots: Set<String>
    ) -> Bool {
        guard !roots.isEmpty else { return false }
        if roots.contains(path) {
            return true
        }

        var candidate = path
        while let slashIndex = candidate.lastIndex(of: "/") {
            candidate = String(candidate[..<slashIndex])
            if candidate.isEmpty {
                return false
            }
            if roots.contains(candidate) {
                return true
            }
        }

        return false
    }

    nonisolated private static func deduplicatedRecords(_ records: [FileRecord]) -> [FileRecord] {
        var recordsByPath: [String: FileRecord] = [:]
        recordsByPath.reserveCapacity(records.count)

        for record in records {
            recordsByPath[record.path] = record
        }

        return Array(recordsByPath.values)
    }

    nonisolated static func preparedRescanPaths(
        _ paths: [String],
        settings: IndexSettings,
        internalExcludedRoots: Set<String>,
        maxPaths: Int
    ) -> [String] {
        let indexedRoots = Set(settings.roots.map(normalizedPath))
        let indexablePaths = paths.compactMap { path -> String? in
            let normalized = normalizedPath(path)
            guard !normalized.isEmpty else { return nil }
            guard !indexedRoots.contains(normalized) else { return nil }
            guard !shouldReplace(normalized, roots: internalExcludedRoots) else { return nil }
            guard settings.shouldIndex(path: normalized, name: URL(fileURLWithPath: normalized).lastPathComponent) else {
                return nil
            }
            return normalized
        }

        return compactedRescanPaths(indexablePaths, indexedRoots: settings.roots, maxPaths: maxPaths)
    }

    nonisolated static func compactedRescanPaths(
        _ paths: [String],
        indexedRoots: [String],
        maxPaths: Int
    ) -> [String] {
        let normalizedPaths = paths
            .map(normalizedPath)
            .filter { !$0.isEmpty }
        guard !normalizedPaths.isEmpty else { return [] }

        let sortedPaths = Array(Set(normalizedPaths)).sorted()
        var compacted: [String] = []
        compacted.reserveCapacity(sortedPaths.count)

        for path in sortedPaths {
            if compacted.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                continue
            }
            compacted.append(path)
        }

        guard compacted.count > maxPaths, maxPaths > 0 else {
            return compacted
        }

        let roots = indexedRoots.map(normalizedPath).filter { !$0.isEmpty }
        let promotedParents = compacted.map { promotedRescanParent(for: $0, indexedRoots: roots) }
        let parentCompacted = Array(Set(promotedParents)).sorted()
        if parentCompacted.count <= maxPaths {
            return parentCompacted
        }

        return roots.isEmpty ? Array(parentCompacted.prefix(maxPaths)) : roots
    }

    nonisolated private static func promotedRescanParent(for path: String, indexedRoots: [String]) -> String {
        for root in indexedRoots where path == root || path.hasPrefix(root + "/") {
            let relativePath = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
            guard let firstComponent = components.first else { return root }
            return root + "/" + firstComponent
        }

        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    nonisolated private static func normalizedPath(_ path: String) -> String {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        guard normalized.count > 1, normalized.hasSuffix("/") else { return normalized }
        return String(normalized.dropLast())
    }

    nonisolated private static func latestDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.none, .none):
            return nil
        case (.some(let date), .none), (.none, .some(let date)):
            return date
        case (.some(let lhs), .some(let rhs)):
            return max(lhs, rhs)
        }
    }

    private func elapsedMilliseconds(since startedAt: CFAbsoluteTime) -> Double {
        (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
    }

    private func filterInternalPaths(_ paths: [String]) -> [String] {
        let excludedRoots = internalExcludedRoots
        return paths.filter { path in
            let normalized = Self.normalizedPath(path)
            return !Self.shouldReplace(normalized, roots: excludedRoots)
        }
    }

    private func filterInternalRecords(from records: [FileRecord]) -> [FileRecord] {
        let excludedRoots = internalExcludedRoots
        return records.filter { record in
            !Self.shouldReplace(Self.normalizedPath(record.path), roots: excludedRoots)
        }
    }

    private func filterIndexSettingsRecords(from records: [FileRecord]) -> [FileRecord] {
        records.filter { record in
            settings.shouldIndex(path: record.path, name: record.name)
        }
    }

    private func filterPermissionRestrictedRecords(from records: [FileRecord]) -> [FileRecord] {
        guard !permissionStatus.fullDiskAccessGranted else { return records }
        return records.filter { record in
            !Self.isProtectedAppDataPath(record.path)
        }
    }

    private func handlePermissionStatusChanged(previous: PermissionStatus, current: PermissionStatus) {
        if !current.fullDiskAccessGranted {
            recordsStorage = filterPermissionRestrictedRecords(from: recordsStorage)
            indexedRecordCount = recordsStorage.count
            refreshResults(showActivity: false)
            return
        }

        guard !previous.fullDiskAccessGranted, isMemoryIndexLoaded else { return }
        Task { [weak self] in
            await self?.reloadMemoryIndexForPermissionUpgrade()
        }
    }

    private func reloadMemoryIndexForPermissionUpgrade() async {
        do {
            let loadedRecords = try await store.loadAll()
            let scopedRecords = filterIndexSettingsRecords(from: loadedRecords)
            recordsStorage = filterPermissionRestrictedRecords(from: scopedRecords)
            indexedRecordCount = recordsStorage.count
            refreshResults(showActivity: false)
        } catch {
            lastError = error.localizedDescription
            state = .degraded(error.localizedDescription)
        }
    }

    nonisolated static func isProtectedAppDataPath(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let protectedRoots = [
            "\(home)/Library/Application Support",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Containers",
            "\(home)/Library/Mail",
            "\(home)/Library/Messages",
            "\(home)/Library/Safari",
            "\(home)/Library/Keychains"
        ]

        for root in protectedRoots {
            if normalized == root || normalized.hasPrefix(root + "/") {
                return true
            }
        }
        return false
    }

    private func writeLastRescanSnapshot(paths: [String]) {
        let directory = diagnosticsDirectoryURL
        let url = directory.appendingPathComponent("LastRescan.txt")
        let payload = ([
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Raw FSEvents count: \(lastFSEventBatchCount.map(String.init) ?? "-")",
            "Filtered FSEvents count: \(lastFilteredFSEventBatchCount.map(String.init) ?? "-")"
        ] + paths.prefix(40).map { "Path: \($0)" }).joined(separator: "\n")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? payload.write(to: url, atomically: true, encoding: .utf8)
    }

    private var internalExcludedRoots: Set<String> {
        var roots: Set<String> = [
            Self.normalizedPath(databaseURL.path),
            Self.normalizedPath(databaseURL.path + "-wal"),
            Self.normalizedPath(databaseURL.path + "-shm"),
            Self.normalizedPath(diagnosticsDirectoryURL.path)
        ]
        if databaseDirectoryURL.lastPathComponent == "Needle" {
            roots.insert(Self.normalizedPath(databaseDirectoryURL.path))
        }
        return roots
    }

    private func formattedMetric(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.2f", value)
    }
}

private final class ModelBox: @unchecked Sendable {
    @MainActor weak var model: SearchAppModel?
}

final class BackgroundEventBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let pathLimit: Int
    private var isBackground = false
    private var paths = Set<String>()
    private var requiresFullRescan = false
    private var reason: String?

    init(pathLimit: Int) {
        self.pathLimit = pathLimit
    }

    func enterBackground() {
        lock.withLock {
            isBackground = true
        }
    }

    func enqueueIfBackground(_ update: FSEventsUpdate) -> Bool {
        lock.withLock {
            guard isBackground else { return false }

            if update.requiresFullRescan {
                requiresFullRescan = true
                reason = update.reason
                paths.removeAll()
                return true
            }

            guard !requiresFullRescan else { return true }
            guard paths.count + update.paths.count <= pathLimit else {
                requiresFullRescan = true
                reason = "后台文件系统事件过多"
                paths.removeAll()
                return true
            }

            paths.formUnion(update.paths)
            return true
        }
    }

    func drainAndEnterForeground() -> FSEventsUpdate? {
        lock.withLock {
            isBackground = false
            defer {
                paths.removeAll()
                requiresFullRescan = false
                reason = nil
            }

            if requiresFullRescan {
                return FSEventsUpdate(paths: [], requiresFullRescan: true, reason: reason)
            }

            guard !paths.isEmpty else { return nil }
            return FSEventsUpdate(paths: Array(paths), requiresFullRescan: false, reason: nil)
        }
    }
}

public extension Notification.Name {
    static let needleDidUnloadForegroundResources = Notification.Name("NeedleDidUnloadForegroundResources")
}

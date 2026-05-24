@preconcurrency import AppKit
import QuickLookUI
import SearchCore
import SwiftUI
import UniformTypeIdentifiers

struct SearchWindow: View {
    @Bindable var model: SearchAppModel
    let shortcutController: GlobalShortcutController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: FileRecord.ID?
    @State private var showSettings = false
    @State private var showFilters = false
    @State private var showPermissionGuide = false
    @State private var showIndexCompleted = false
    @State private var indexCompletionGeneration = 0
    @AppStorage("previewPaneWidth") private var previewPaneWidth = 300.0

    private var selectedRecord: FileRecord? {
        model.results.first { $0.id == selection }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()
                content
            }
            .allowsHitTesting(!showSettings)

            if showSettings {
                settingsOverlay
                    .transition(reduceMotion ? .opacity : .settingsPanel)
                    .zIndex(2)
            }
        }
        .animation(settingsAnimation, value: showSettings)
        .frame(minWidth: 860, idealWidth: 980, minHeight: 560, idealHeight: 680)
        .background(.regularMaterial)
        .background {
            WindowAccessor { window in
                shortcutController.bind(window: window)
                window.title = "Needle"
                window.isMovableByWindowBackground = true
            }
        }
        .sheet(isPresented: $showPermissionGuide) {
            PermissionGuideView(model: model, isPresented: $showPermissionGuide)
        }
        .onChange(of: model.results) { _, newResults in
            if selection == nil || !newResults.contains(where: { $0.id == selection }) {
                selection = newResults.first?.id
            }
        }
        .onChange(of: selection) { _, _ in
            if let selectedRecord {
                QuickLookPreviewController.shared.updateVisiblePreview(record: selectedRecord)
            }
        }
        .onChange(of: model.state) { oldState, newState in
            handleIndexStateChange(from: oldState, to: newState)
        }
        .onAppear {
            NeedleAppDelegate.settingsHandler = {
                shortcutController.showSearchWindow()
                openSettings()
            }
            model.refreshPermissionStatus()
            showPermissionGuide = !model.appSettings.hasCompletedOnboarding
        }
        .onAppActivate {
            model.refreshPermissionStatus()
        }
        .onExitCommand {
            if showSettings {
                closeSettings()
            }
        }
        .background {
            SpaceKeyPreviewMonitor(isEnabled: !showSettings && !showPermissionGuide) {
                if let selectedRecord {
                    QuickLookPreviewController.shared.preview(record: selectedRecord)
                }
            }
        }
    }

    private var settingsOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.clear)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeSettings()
                    }

                SettingsPanel(model: model)
                .frame(
                    width: min(proxy.size.width - 160, 660),
                    height: min(proxy.size.height - 64, 600)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 64)
                .padding(.vertical, 28)
            }
        }
    }
}

private struct SettingsPanelMotion: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale, anchor: .center)
            .offset(y: y)
    }
}

private extension AnyTransition {
    static var settingsPanel: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: SettingsPanelMotion(opacity: 0, scale: 0.965, y: 0),
                identity: SettingsPanelMotion(opacity: 1, scale: 1, y: 0)
            ),
            removal: .modifier(
                active: SettingsPanelMotion(opacity: 0, scale: 0.985, y: 0),
                identity: SettingsPanelMotion(opacity: 1, scale: 1, y: 0)
            )
        )
    }
}

private extension Animation {
    static var settingsPanel: Animation {
        .smooth(duration: 0.24, extraBounce: 0)
    }
}

private extension SearchWindow {
    var settingsAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .settingsPanel
    }

    func openSettings() {
        withAnimation(settingsAnimation) {
            showSettings = true
        }
    }

    func closeSettings() {
        withAnimation(settingsAnimation) {
            showSettings = false
        }
    }

    var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("搜索文件、文件夹或路径", text: $model.queryText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .onSubmit {
                        if let selectedRecord {
                            model.open(selectedRecord)
                        }
                    }

                HStack(spacing: 6) {
                    HelpTip(
                        title: "搜索语法",
                        steps: [
                            "直接输入关键词：按文件名和路径搜索。",
                            "输入完整词组时可使用引号，例如 “项目 报告”。",
                            "按扩展名过滤：输入 .swift 或 ext:swift。",
                            "通配符搜索：输入 *.rpm、README* 或 *report*.pdf。",
                            "正则搜索：输入 re:^IMG_.*\\.jpg$。",
                            "更多筛选选项在右侧滑杆按钮中。"
                        ]
                    )

                    headerIconButton(systemName: "slider.horizontal.3") {
                        showFilters.toggle()
                    }
                    .help("筛选")
                    .popover(isPresented: $showFilters, arrowEdge: .bottom) {
                        FilterPopover(model: model)
                    }

                    headerIconButton(systemName: "gearshape") {
                        openSettings()
                    }
                    .help("设置")
                }
            }

            HStack {
                if let queryWarning = model.queryWarning {
                    Label(queryWarning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else {
                    Label(".swift  *.rpm  re:^IMG_.*\\.jpg$", systemImage: "sparkle.magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help("示例：按扩展名输入 .swift；通配符输入 *.rpm；正则输入 re:^IMG_.*\\.jpg$")
                }
                Spacer()
                statusView
            }
            .font(.callout)
        }
        .padding(22)
    }

    private func headerIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        Group {
            if model.settings.roots.isEmpty {
                ContentUnavailableView {
                    Label("选择要索引的文件夹", systemImage: "folder.badge.plus")
                } description: {
                    Text("建议先选择一个小目录测试。授予完全磁盘访问权限后，再加入个人文件夹。")
                } actions: {
                    Button("打开设置") {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let width = clampedPreviewPaneWidth(totalWidth: proxy.size.width)
                    HStack(spacing: 0) {
                        ResultsList(
                        results: model.results,
                        selection: $selection,
                        open: model.open,
                        openWithApplicationPicker: model.openWithApplicationPicker,
                        quickLook: { QuickLookPreviewController.shared.preview(record: $0) },
                        reveal: model.revealInFinder,
                        openParentFolder: model.openParentFolder,
                        copyPath: model.copyPath,
                        copyName: model.copyName,
                        copyParentPath: model.copyParentPath
                    )
                    .frame(minWidth: 520)

                        SplitResizeHandle(
                            previewPaneWidth: $previewPaneWidth,
                            defaultWidth: defaultPreviewPaneWidth,
                            minWidth: minPreviewPaneWidth,
                            maxWidth: maxPreviewPaneWidth(totalWidth: proxy.size.width)
                        )

                        PreviewPane(record: selectedRecord)
                            .frame(width: width)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if showIndexCompleted {
            Label("已完成索引", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if model.indexNeedsRebuild {
            Label("需要重建索引", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        } else {
            switch model.state {
        case .idle:
            Text("未开始")
                .foregroundStyle(.secondary)
        case .loading:
            Label("正在加载索引", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .scanning(let processed):
            Label("正在扫描 \(processed.formatted()) 项", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        case .watching:
            Label("已索引 \(model.records.count.formatted()) 项", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .permissionBlocked:
            Button("授予完全磁盘访问权限") {
                model.openPrivacySettings()
            }
        case .degraded(let message):
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(1)
            }
        }
    }

    private func handleIndexStateChange(from oldState: IndexerState, to newState: IndexerState) {
        guard case .scanning = oldState else { return }

        switch newState {
        case .watching:
            showTemporaryIndexCompletion()
        case .idle, .loading, .scanning, .permissionBlocked, .degraded:
            showIndexCompleted = false
        }
    }

    private func showTemporaryIndexCompletion() {
        showIndexCompleted = true
        indexCompletionGeneration += 1
        let generation = indexCompletionGeneration

        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                guard indexCompletionGeneration == generation else { return }
                showIndexCompleted = false
            }
        }
    }
}

private extension SearchWindow {
    var defaultPreviewPaneWidth: Double { 300 }
    var minPreviewPaneWidth: Double { 240 }
    var minResultsWidth: Double { 520 }

    func maxPreviewPaneWidth(totalWidth: CGFloat) -> Double {
        let availableWidth = Double(totalWidth)
        return max(
            minPreviewPaneWidth,
            min(availableWidth * 0.45, availableWidth - minResultsWidth, 520)
        )
    }

    func clampedPreviewPaneWidth(totalWidth: CGFloat) -> CGFloat {
        CGFloat(previewPaneWidth.clamped(to: minPreviewPaneWidth...maxPreviewPaneWidth(totalWidth: totalWidth)))
    }
}

private struct FilterPopover: View {
    @Bindable var model: SearchAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("筛选")
                    .font(.headline)

                Picker("类型", selection: $model.kindFilter) {
                    Text("全部").tag(KindFilter.all)
                    Text("文件").tag(KindFilter.files)
                    Text("文件夹").tag(KindFilter.folders)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("搜索范围")
                    .font(.headline)
                Toggle("搜索路径", isOn: $model.matchPath)
                Text(model.matchPath ? "同时匹配文件名和完整路径。" : "只匹配文件名。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

private struct SplitResizeHandle: View {
    @Binding var previewPaneWidth: Double
    let defaultWidth: Double
    let minWidth: Double
    let maxWidth: Double

    var body: some View {
        SplitResizeHandleView(
            previewPaneWidth: $previewPaneWidth,
            defaultWidth: defaultWidth,
            minWidth: minWidth,
            maxWidth: maxWidth
        )
            .frame(width: 9)
            .frame(maxHeight: .infinity)
            .accessibilityLabel("调整预览栏宽度")
            .help("拖动调整预览栏宽度，双击恢复默认宽度")
    }
}

private struct SplitResizeHandleView: NSViewRepresentable {
    @Binding var previewPaneWidth: Double
    let defaultWidth: Double
    let minWidth: Double
    let maxWidth: Double

    func makeNSView(context: Context) -> SplitResizeHandleNSView {
        SplitResizeHandleNSView()
    }

    func updateNSView(_ nsView: SplitResizeHandleNSView, context: Context) {
        nsView.previewPaneWidth = previewPaneWidth
        nsView.defaultWidth = defaultWidth
        nsView.minWidth = minWidth
        nsView.maxWidth = maxWidth
        nsView.onWidthChange = { previewPaneWidth = $0 }
    }
}

private final class SplitResizeHandleNSView: NSView {
    var previewPaneWidth = 300.0
    var defaultWidth = 300.0
    var minWidth = 240.0
    var maxWidth = 520.0
    var onWidthChange: ((Double) -> Void)?

    private var mouseDownX = 0.0
    private var mouseDownPreviewWidth = 300.0
    private var isHovering = false
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            setPreviewWidth(defaultWidth)
            return
        }

        mouseDownX = event.locationInWindow.x
        mouseDownPreviewWidth = previewPaneWidth
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let delta = event.locationInWindow.x - mouseDownX
        setPreviewWidth(mouseDownPreviewWidth - delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color: NSColor = isHovering || isDragging ? .controlAccentColor.withAlphaComponent(0.45) : .separatorColor
        color.setFill()
        let lineRect = NSRect(x: floor(bounds.midX), y: 0, width: 1, height: bounds.height)
        lineRect.fill()
    }

    private func setPreviewWidth(_ width: Double) {
        let clampedWidth = width.clamped(to: minWidth...maxWidth)
        previewPaneWidth = clampedWidth
        onWidthChange?(clampedWidth)
        needsDisplay = true
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

struct ResultsList: View {
    let results: [FileRecord]
    @Binding var selection: FileRecord.ID?
    let open: (FileRecord) -> Void
    let openWithApplicationPicker: (FileRecord) -> Void
    let quickLook: (FileRecord) -> Void
    let reveal: (FileRecord) -> Void
    let openParentFolder: (FileRecord) -> Void
    let copyPath: (FileRecord) -> Void
    let copyName: (FileRecord) -> Void
    let copyParentPath: (FileRecord) -> Void
    @State private var sortOrder = [KeyPathComparator<FileRecord>]()

    private var displayedResults: [FileRecord] {
        guard let primaryComparator = sortOrder.first else {
            return results
        }

        return results.sorted { lhs, rhs in
            let lhsGroup = folderFirstGroup(for: lhs)
            let rhsGroup = folderFirstGroup(for: rhs)
            if lhsGroup != rhsGroup {
                return lhsGroup < rhsGroup
            }

            let primaryComparison = primaryComparator.compare(lhs, rhs)
            if primaryComparison != .orderedSame {
                return primaryComparison == .orderedAscending
            }

            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    var body: some View {
        Table(displayedResults, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("名称", value: \.needleSortName) { record in
                HStack(spacing: 8) {
                    FileIconView(record: record, mode: .list, size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.name)
                            .fontWeight(.medium)
                        Text(record.parentPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
            }
            TableColumn("类型", value: \.needleSortKind) { record in
                Text(displayKind(record.kind))
                    .foregroundStyle(.secondary)
            }
            .width(70)
            TableColumn("大小", value: \.needleSortSize) { record in
                Text(record.kind == .folder ? "-" : ByteCountFormatter.string(fromByteCount: record.size, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("修改时间", value: \.needleSortModifiedAt) { record in
                Text(record.modifiedAt, style: .date)
                    .foregroundStyle(.secondary)
            }
            .width(110)
        }
        .disableHorizontalScrollIndicators()
        .contextMenu(forSelectionType: FileRecord.ID.self) { selectedIDs in
            if let record = displayedResults.first(where: { selectedIDs.contains($0.id) }) {
                Button("打开") { open(record) }
                Button("打开方式...") { openWithApplicationPicker(record) }
                Button("快速预览") { quickLook(record) }
                Divider()
                Button("在 Finder 中显示") { reveal(record) }
                Button("打开父文件夹") { openParentFolder(record) }
                Divider()
                Button("复制路径") { copyPath(record) }
                Button("复制文件名") { copyName(record) }
                Button("复制父文件夹路径") { copyParentPath(record) }
            }
        } primaryAction: { selectedIDs in
            if let record = displayedResults.first(where: { selectedIDs.contains($0.id) }) {
                open(record)
            }
        }
        .onDrag {
            guard
                let selection,
                let record = displayedResults.first(where: { $0.id == selection })
            else {
                return NSItemProvider()
            }
            return NSItemProvider(contentsOf: URL(fileURLWithPath: record.path)) ?? NSItemProvider()
        }
    }

    private func folderFirstGroup(for record: FileRecord) -> Int {
        switch record.kind {
        case .folder:
            return 0
        case .file:
            return 1
        case .other:
            return 2
        }
    }

    private func displayKind(_ kind: FileKind) -> String {
        switch kind {
        case .file:
            return "文件"
        case .folder:
            return "文件夹"
        case .other:
            return "其他"
        }
    }
}

private extension FileRecord {
    var needleSortName: String {
        name
    }

    var needleSortKind: Int {
        switch kind {
        case .folder:
            return 0
        case .file:
            return 1
        case .other:
            return 2
        }
    }

    var needleSortSize: Int64 {
        kind == .folder ? -1 : size
    }

    var needleSortModifiedAt: Date {
        modifiedAt
    }
}

private struct HorizontalScrollIndicatorDisabler: NSViewRepresentable {
    final class Coordinator {
        var didConfigure = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            disableHorizontalScrollers(near: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.didConfigure else { return }
        DispatchQueue.main.async {
            disableHorizontalScrollers(near: nsView, coordinator: context.coordinator)
        }
    }

    private func disableHorizontalScrollers(near view: NSView, coordinator: Coordinator) {
        guard !coordinator.didConfigure else { return }

        var current: NSView? = view
        while let node = current {
            if let scrollView = node as? NSScrollView {
                scrollView.hasHorizontalScroller = false
                scrollView.horizontalScrollElasticity = .none
                scrollView.autohidesScrollers = true
                coordinator.didConfigure = true
                return
            }
            current = node.superview
        }

        view.window?.contentView?.subviewsRecursive.forEach { node in
            guard let scrollView = node as? NSScrollView else { return }
            if scrollView.documentView is NSTableView {
                scrollView.hasHorizontalScroller = false
                scrollView.horizontalScrollElasticity = .none
                scrollView.autohidesScrollers = true
                coordinator.didConfigure = true
            }
        }
    }
}

private extension NSView {
    var subviewsRecursive: [NSView] {
        subviews + subviews.flatMap(\.subviewsRecursive)
    }
}

private extension View {
    func disableHorizontalScrollIndicators() -> some View {
        background(HorizontalScrollIndicatorDisabler())
    }
}

private struct SpaceKeyPreviewMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let previewSelectedRecord: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(near: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.previewSelectedRecord = previewSelectedRecord
        context.coordinator.install(near: nsView)
    }

    final class Coordinator {
        var isEnabled = true
        var previewSelectedRecord: (@MainActor () -> Void)?
        private weak var view: NSView?
        private var monitor: Any?

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func install(near view: NSView) {
            self.view = view
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.shouldPreview(for: event) else {
                    return event
                }

                self.previewSelectedRecord?()
                return nil
            }
        }

        private func shouldPreview(for event: NSEvent) -> Bool {
            guard isEnabled, event.keyCode == 49 else { return false }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return false }
            guard let window = view?.window, event.window === window else { return false }
            guard !(window.firstResponder is NSTextView) else { return false }
            return true
        }
    }
}

struct PreviewPane: View {
    let record: FileRecord?
    @State private var folderSizeState = FolderSizeState.idle
    @State private var folderSizeTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let record {
                HStack(alignment: .center, spacing: 12) {
                    FileIconView(record: record, mode: .preview, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(displayKind(record.kind))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 2)

                metadataGroup(for: record)

                QuickLookPreview(url: URL(fileURLWithPath: record.path))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.quaternary)
                    }
                    .frame(minHeight: 180)
            } else {
                ContentUnavailableView("未选择文件", systemImage: "doc.text.magnifyingglass")
            }
            Spacer()
        }
        .padding(18)
        .onAppear {
            startFolderSizeIfNeeded(for: record)
        }
        .onChange(of: record?.id) { _, _ in
            startFolderSizeIfNeeded(for: record)
        }
        .onDisappear {
            folderSizeTask?.cancel()
        }
    }

    private func metadataGroup(for record: FileRecord) -> some View {
        VStack(spacing: 0) {
            metadataRow("位置", record.parentPath, lineLimit: 2)
            PreviewMetadataDivider()
            sizeMetadata(for: record)
            PreviewMetadataDivider()
            metadataRow("修改时间", record.modifiedAt.formatted(date: .abbreviated, time: .shortened))
            if let lastOpenedAt = record.lastOpenedAt {
                PreviewMetadataDivider()
                metadataRow("最近打开", lastOpenedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if record.openCount > 0 {
                PreviewMetadataDivider()
                metadataRow("打开次数", "\(record.openCount.formatted()) 次")
            }
        }
        .padding(.vertical, 2)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary)
        }
    }

    @ViewBuilder
    private func sizeMetadata(for record: FileRecord) -> some View {
        if record.kind == .folder {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                metadataTitle("大小")
                Spacer(minLength: 8)
                folderSizeValue(for: record)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        } else {
            metadataRow("大小", ByteCountFormatter.string(fromByteCount: record.size, countStyle: .file))
        }
    }

    @ViewBuilder
    private func folderSizeValue(for record: FileRecord) -> some View {
        switch folderSizeState {
        case .idle:
            Text("-")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .calculating:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在计算")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .finished(let size):
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .font(.callout)
                .textSelection(.enabled)
        case .failed:
            HStack(spacing: 8) {
                Text("无法计算")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("重试") {
                    calculateFolderSize(for: record)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    private func metadataRow(_ title: String, _ value: String, lineLimit: Int = 1) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            metadataTitle(title)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout)
                .multilineTextAlignment(.trailing)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func metadataTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .leading)
    }

    private func displayKind(_ kind: FileKind) -> String {
        switch kind {
        case .file:
            return "文件"
        case .folder:
            return "文件夹"
        case .other:
            return "其他"
        }
    }

    private func startFolderSizeIfNeeded(for record: FileRecord?) {
        resetFolderSize()
        guard let record, record.kind == .folder else { return }
        calculateFolderSize(for: record)
    }

    private func resetFolderSize() {
        folderSizeTask?.cancel()
        folderSizeTask = nil
        folderSizeState = .idle
    }

    private func calculateFolderSize(for record: FileRecord) {
        folderSizeTask?.cancel()
        folderSizeState = .calculating
        let path = record.path

        folderSizeTask = Task {
            let size = await DirectorySizeCalculator.calculate(path: path)
            guard !Task.isCancelled else { return }
            folderSizeState = size.map(FolderSizeState.finished) ?? .failed
        }
    }
}

private struct PreviewMetadataDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 76)
    }
}

private enum FolderSizeState: Equatable {
    case idle
    case calculating
    case finished(Int64)
    case failed
}

private enum DirectorySizeCalculator {
    static func calculate(path: String) async -> Int64? {
        await Task.detached(priority: .utility) {
            let rootURL = URL(fileURLWithPath: path)
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
            guard let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: Array(keys),
                options: [],
                errorHandler: { _, _ in true }
            ) else {
                return nil
            }

            var total: Int64 = 0
            while let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled {
                    return nil
                }

                guard
                    let values = try? fileURL.resourceValues(forKeys: keys),
                    values.isRegularFile == true
                else {
                    continue
                }

                let size = values.totalFileAllocatedSize ?? values.fileSize ?? 0
                total += Int64(size)
            }

            return total
        }.value
    }
}

struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
    }
}

@MainActor
private final class QuickLookPreviewController: NSObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreviewController()

    private var previewURL: NSURL?

    func preview(record: FileRecord) {
        previewURL = URL(fileURLWithPath: record.path) as NSURL
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func updateVisiblePreview(record: FileRecord) {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        previewURL = URL(fileURLWithPath: record.path) as NSURL
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL
    }
}

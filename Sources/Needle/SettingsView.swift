import AppKit
import SearchCore
import ServiceManagement
import SwiftUI

struct SettingsPanel: View {
    @Bindable var model: SearchAppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置")
                        .font(.title3.bold())
                    Text("配置索引范围、权限、快捷键和启动行为。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 11)

            Divider()

            SettingsView(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.quaternary)
        }
        .shadow(color: .black.opacity(0.16), radius: 34, y: 18)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {}
    }
}

struct SettingsView: View {
    @Bindable var model: SearchAppModel
    @State private var selectedRoot: String?
    @State private var loginItemError: String?
    @State private var newExcludedPattern = ""
    @State private var rebuildStartedFromSettings = false
    @State private var showRebuildCompleted = false
    @State private var rebuildCompletionGeneration = 0
    @State private var showDiagnosticsExported = false
    @State private var diagnosticsExportGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    permissionSection
                    behaviorSection
                    indexingSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .background(SettingsScrollIndicatorDisabler())

            rebuildBar
        }
        .onChange(of: model.state) { oldState, newState in
            handleIndexStateChange(from: oldState, to: newState)
        }
    }

    private var permissionSection: some View {
        settingsSection(
            title: "权限引导",
            caption: "完全磁盘访问用于读取受保护目录；辅助功能用于监听全局快捷键。"
        ) {
            preferenceGroup {
                preferenceRow(
                    icon: "shield",
                    title: "完全磁盘访问",
                    description: "用于读取桌面、文稿、下载等受保护目录。"
                ) {
                    HStack(spacing: 8) {
                        StatusBadge(
                            isOn: model.permissionStatus.fullDiskAccessGranted,
                            onText: "已开启",
                            offText: "未确认"
                        )
                        Button("打开") {
                            model.openPrivacySettings()
                        }
                        HelpTip(
                            title: "为 Needle 授予完全磁盘访问",
                            steps: [
                                "在系统设置列表下方点击 +。",
                                "选择 Needle.app 并确认。",
                                "输入密码后重启 Needle。",
                                "回到这里点击“刷新状态”。"
                            ]
                        )
                    }
                }

                PreferenceDivider()

                preferenceRow(
                    icon: "keyboard",
                    title: "辅助功能",
                    description: "用于监听全局快捷键，不会读取键盘输入内容。"
                ) {
                    HStack(spacing: 8) {
                        StatusBadge(
                            isOn: model.permissionStatus.accessibilityGranted,
                            onText: "已开启",
                            offText: "未开启"
                        )
                        Button("打开") {
                            model.openAccessibilitySettings()
                        }
                        HelpTip(
                            title: "为 Needle 授予辅助功能权限",
                            steps: [
                                "在系统设置中找到 Needle。",
                                "打开 Needle 右侧开关。",
                                "如系统提示，输入密码确认。",
                                "回到这里点击“刷新状态”。"
                            ]
                        )
                    }
                }
            }

            HStack {
                Spacer()
                Button("刷新状态") {
                    model.refreshPermissionStatus()
                }
                .controlSize(.small)
            }
        }
    }

    private var behaviorSection: some View {
        settingsSection(title: "行为") {
            preferenceGroup {
                preferenceRow(
                    icon: "power",
                    title: "登录时自动启动",
                    description: "开机后保持菜单栏服务和索引监听。"
                ) {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                }

                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }

                PreferenceDivider()

                preferenceRow(
                    icon: "rectangle.on.rectangle.slash",
                    title: "关闭窗口后保持后台运行",
                    description: "关闭搜索窗口或按 ⌘ W 时隐藏到后台；使用 ⌘ Q 或菜单栏退出才会真正退出。"
                ) {
                    Toggle("", isOn: $model.appSettings.keepRunningAfterWindowClose)
                        .labelsHidden()
                }

                PreferenceDivider()

                preferenceRow(
                    icon: "keyboard.chevron.compact.down",
                    title: "⌘Q 关闭窗口并保留快捷键",
                    description: "开启后，按 ⌘Q 只会关闭搜索窗口，Needle 继续在后台保持全局快捷键可用。"
                ) {
                    Toggle("", isOn: $model.appSettings.commandQHidesWindow)
                        .labelsHidden()
                }

                PreferenceDivider()

                preferenceRow(
                    icon: "arrow.down.circle",
                    title: "自动检查更新",
                    description: "启动后后台检查是否有新版本，只提示更新，不会自动下载安装。\n当前状态：\(updateStatusDescription)"
                ) {
                    HStack(spacing: 8) {
                        Button(updateActionButtonTitle) {
                            if case .updateAvailable = model.updateCheckState {
                                model.openLatestReleasePage()
                            } else {
                                model.checkForUpdatesNow()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.updateCheckState == .checking)

                        Toggle("", isOn: $model.appSettings.autoCheckUpdates)
                            .labelsHidden()
                    }
                }

                PreferenceDivider()

                preferenceRow(
                    icon: "command",
                    title: "全局快捷键",
                    description: "使用 ⌘ ⇧ F 从任何地方打开 Needle。"
                ) {
                    HStack(spacing: 8) {
                        Text("⌘ ⇧ F")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        StatusBadge(
                            isOn: model.appSettings.globalShortcutEnabled && model.permissionStatus.accessibilityGranted,
                            onText: "可用",
                            offText: model.appSettings.globalShortcutEnabled ? "等待权限" : "已关闭"
                        )
                        Toggle("", isOn: $model.appSettings.globalShortcutEnabled)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    private var updateStatusDescription: String {
        let versionPrefix: String
        if let latestKnownVersion = model.latestKnownVersion {
            versionPrefix = "当前 \(model.currentAppVersion) / 最新 \(latestKnownVersion)"
        } else {
            versionPrefix = "当前 \(model.currentAppVersion) / 最新 -"
        }

        let checkedAtSuffix: String
        if let checkedAt = model.lastUpdateCheckedAt {
            checkedAtSuffix = "（上次检查：\(checkedAt.formatted(date: .omitted, time: .shortened))）"
        } else {
            checkedAtSuffix = "（尚未检查）"
        }

        switch model.updateCheckState {
        case .idle:
            return "\(versionPrefix)，尚未检查更新\(checkedAtSuffix)"
        case .checking:
            return "\(versionPrefix)，正在检查更新…"
        case .upToDate:
            return "\(versionPrefix)，当前已是最新版本\(checkedAtSuffix)"
        case .updateAvailable(let version, _):
            return "\(versionPrefix)，发现新版本 \(version)"
        case .failed(let message):
            return "\(versionPrefix)，\(message)\(checkedAtSuffix)"
        }
    }

    private var updateActionButtonTitle: String {
        switch model.updateCheckState {
        case .updateAvailable:
            return "查看新版本"
        case .checking:
            return "检查中…"
        default:
            return "立即检查"
        }
    }

    private var indexingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsCard(
                title: "索引位置",
                showsRebuildRequired: model.indexNeedsRebuild,
                helpTitle: "索引位置说明",
                helpSteps: [
                    "Needle 只会扫描这里列出的文件夹。",
                    "建议先添加常用目录，确认速度和结果后再扩大范围。",
                    "索引位置越多，初次扫描耗时越长。"
                ]
            ) {
                if model.settings.roots.isEmpty {
                    ContentUnavailableView {
                        Label("还没有索引位置", systemImage: "folder.badge.plus")
                    } description: {
                        Text("添加一个文件夹后，Needle 才会开始建立本地索引。")
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 8) {
                        ForEach(model.settings.roots, id: \.self) { root in
                            indexRootRow(root)
                        }
                    }
                }

                HStack {
                    Button {
                        addFolder()
                    } label: {
                        Label("添加文件夹", systemImage: "folder.badge.plus")
                    }

                    Button {
                        model.addRoot(FileManager.default.homeDirectoryForCurrentUser)
                    } label: {
                        Label("个人文件夹", systemImage: "house")
                    }

                    Button {
                        model.addRoot(URL(fileURLWithPath: "/Applications", isDirectory: true))
                    } label: {
                        Label("应用程序", systemImage: "square.grid.2x2")
                    }

                    Button(role: .destructive) {
                        if let selectedRoot {
                            model.removeRoot(selectedRoot)
                        }
                    } label: {
                        Label("移除", systemImage: "minus.circle")
                    }
                    .disabled(selectedRoot == nil)
                }
                .buttonStyle(.bordered)
            }

            settingsCard(
                title: "索引规则",
                showsRebuildRequired: model.indexNeedsRebuild,
                helpTitle: "索引规则说明",
                helpSteps: [
                    "控制哪些文件会进入索引。",
                    "包含隐藏文件会让结果更完整，但也会带来更多系统和配置文件。",
                    "排除开发缓存和依赖目录可以保持搜索结果更干净。"
                ]
            ) {
                Toggle("包含隐藏文件", isOn: $model.settings.includeHiddenFiles)

                VStack(alignment: .leading, spacing: 10) {
                    Text("排除项")
                        .font(.subheadline.weight(.semibold))
                    ExclusionEditor(
                        patterns: $model.settings.excludedNamePatterns,
                        newPattern: $newExcludedPattern,
                        recommendedPatterns: IndexSettings.commonExcludedNamePatterns
                    )
                }
            }

            settingsCard(
                title: "搜索行为",
                helpTitle: "搜索行为说明",
                helpSteps: [
                    "这些选项会影响默认搜索方式。",
                    "默认搜索路径开启后，会同时匹配文件名和完整路径。",
                    "主窗口筛选面板里的临时选择会覆盖默认行为。"
                ]
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("默认搜索路径", isOn: $model.settings.matchPathByDefault)
                    Text("开启后，搜索会同时匹配文件名和完整路径；关闭后默认只匹配文件名。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard(
                title: "诊断",
                helpTitle: "诊断说明",
                helpSteps: [
                    "导出的诊断报告会保存当前索引状态、权限状态和设置摘要。",
                    "日志目录位于 Application Support/Needle/Logs，适合后续排查问题。",
                    "如果程序出现异常、卡顿或权限错误，可以先导出报告再反馈。"
                ]
            ) {
                HStack(spacing: 10) {
                    Button {
                        model.openDiagnosticsFolder()
                    } label: {
                        Label("打开日志目录", systemImage: "folder")
                    }

                    Button {
                        if model.exportDiagnostics() != nil {
                            showTemporaryDiagnosticsExportCompletion()
                        }
                    } label: {
                        Label(diagnosticsExportButtonTitle, systemImage: diagnosticsExportButtonIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(showDiagnosticsExported ? .green : .accentColor)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var rebuildBar: some View {
        HStack(spacing: 12) {
            indexStatusView

            Spacer()

            Button("退出 Needle", role: .destructive) {
                NeedleAppDelegate.terminateNow()
            }
            .buttonStyle(.bordered)

            Button {
                rebuildStartedFromSettings = true
                showRebuildCompleted = false
                Task { await model.rebuildIndex() }
            } label: {
                Label(rebuildButtonTitle, systemImage: rebuildButtonIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(showRebuildCompleted ? .green : .accentColor)
            .disabled(model.settings.roots.isEmpty || isRebuilding || showRebuildCompleted)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.secondary.opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 12)
        }
    }

    @ViewBuilder
    private var indexStatusView: some View {
        if model.indexNeedsRebuild {
            Label("设置已更改，需要重建索引", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        } else {
            switch model.state {
        case .idle:
            Label("未开始索引", systemImage: "tray")
                .foregroundStyle(.secondary)
        case .loading:
            Label("正在加载索引", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .scanning(let processed):
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("正在重建索引，已处理 \(processed.formatted()) 项")
                    .foregroundStyle(.secondary)
            }
        case .watching:
            Label("\(model.indexedRecordCount.formatted()) 个项目", systemImage: "tray.full")
                .foregroundStyle(.secondary)
        case .permissionBlocked:
            Label("部分位置需要权限", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .degraded(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .foregroundStyle(.red)
                .lineLimit(1)
            }
        }
    }

    private var isRebuilding: Bool {
        if case .scanning = model.state {
            return true
        }
        return false
    }

    private var rebuildButtonTitle: String {
        if showRebuildCompleted {
            return "已完成索引"
        }
        return isRebuilding ? "正在重建" : "重建索引"
    }

    private var rebuildButtonIcon: String {
        showRebuildCompleted ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
    }

    private func handleIndexStateChange(from oldState: IndexerState, to newState: IndexerState) {
        guard rebuildStartedFromSettings else { return }

        if case .scanning = newState {
            return
        }

        guard case .scanning = oldState else { return }

        switch newState {
        case .watching:
            showTemporaryRebuildCompletion()
        case .permissionBlocked, .degraded, .idle:
            rebuildStartedFromSettings = false
            showRebuildCompleted = false
        case .loading, .scanning:
            break
        }
    }

    private func showTemporaryRebuildCompletion() {
        rebuildStartedFromSettings = false
        showRebuildCompleted = true
        rebuildCompletionGeneration += 1
        let generation = rebuildCompletionGeneration

        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                guard rebuildCompletionGeneration == generation else { return }
                showRebuildCompleted = false
            }
        }
    }

    private var diagnosticsExportButtonTitle: String {
        showDiagnosticsExported ? "已导出报告" : "导出诊断报告"
    }

    private var diagnosticsExportButtonIcon: String {
        showDiagnosticsExported ? "checkmark.circle.fill" : "square.and.arrow.up"
    }

    private func showTemporaryDiagnosticsExportCompletion() {
        showDiagnosticsExported = true
        diagnosticsExportGeneration += 1
        let generation = diagnosticsExportGeneration

        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                guard diagnosticsExportGeneration == generation else { return }
                showDiagnosticsExported = false
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            model.appSettings.launchAtLogin
        } set: { enabled in
            do {
                try LoginItemController.setEnabled(enabled)
                model.appSettings.launchAtLogin = enabled
                loginItemError = nil
            } catch {
                model.appSettings.launchAtLogin = LoginItemController.isEnabled
                loginItemError = "登录启动设置失败：\(error.localizedDescription)"
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                model.addRoot(url)
            }
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        showsRebuildRequired: Bool = false,
        helpTitle: String,
        helpSteps: [String],
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.headline)
                HelpTip(title: helpTitle, steps: helpSteps)
                if showsRebuildRequired {
                    Label("需要重建", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                Spacer()
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.46), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.quaternary.opacity(0.72))
        }
    }

    private func indexRootRow(_ root: String) -> some View {
        Button {
            selectedRoot = root
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.title3)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text(URL(fileURLWithPath: root).lastPathComponent.isEmpty ? root : URL(fileURLWithPath: root).lastPathComponent)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(root)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                if selectedRoot == root {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(selectedRoot == root ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func settingsSection<Content: View>(
        title: String,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let caption {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
    }

    private func preferenceGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.quaternary.opacity(0.65))
        }
    }

    private func preferenceRow<Trailing: View>(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct PreferenceDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 48)
    }
}

private struct SoftSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .secondary.opacity(0.16), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, 2)
    }
}

private struct SettingsScrollIndicatorDisabler: NSViewRepresentable {
    final class Coordinator {
        var didConfigure = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            hideScroller(near: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !context.coordinator.didConfigure else { return }
        DispatchQueue.main.async {
            hideScroller(near: nsView, coordinator: context.coordinator)
        }
    }

    private func hideScroller(near view: NSView, coordinator: Coordinator) {
        guard !coordinator.didConfigure else { return }

        var current = view.superview
        while let node = current {
            if let scrollView = node as? NSScrollView {
                configure(scrollView)
                coordinator.didConfigure = true
                return
            }
            current = node.superview
        }

        view.window?.contentView?.settingsSubviewsRecursive.forEach { node in
            guard let scrollView = node as? NSScrollView else { return }
            guard !(scrollView.documentView is NSTableView) else { return }
            configure(scrollView)
            coordinator.didConfigure = true
        }
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .automatic
        scrollView.horizontalScrollElasticity = .none
    }
}

private extension NSView {
    var settingsSubviewsRecursive: [NSView] {
        subviews + subviews.flatMap(\.settingsSubviewsRecursive)
    }
}

private struct ExclusionEditor: View {
    @Binding var patterns: [String]
    @Binding var newPattern: String
    let recommendedPatterns: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowTags(tags: patterns) { pattern in
                patterns.removeAll { $0 == pattern }
            }

            if !missingRecommendedPatterns.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("常用排除")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: 8) {
                        ForEach(missingRecommendedPatterns, id: \.self) { pattern in
                            Button {
                                addRecommendedPattern(pattern)
                            } label: {
                                Label(pattern, systemImage: "plus")
                            }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button {
                            addAllRecommendedPatterns()
                        } label: {
                            Label("全部添加", systemImage: "checkmark.circle")
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("例如 node_modules、.git、Library/Caches", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPattern)

                Button {
                    addPattern()
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .disabled(normalizedNewPattern == nil)
            }

            Text("排除项会匹配文件夹或路径片段。修改后请重建索引。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var normalizedNewPattern: String? {
        let value = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard !patterns.contains(value) else { return nil }
        return value
    }

    private var missingRecommendedPatterns: [String] {
        recommendedPatterns.filter { !patterns.contains($0) }
    }

    private func addPattern() {
        guard let value = normalizedNewPattern else { return }
        patterns.append(value)
        newPattern = ""
    }

    private func addRecommendedPattern(_ pattern: String) {
        guard !patterns.contains(pattern) else { return }
        patterns.append(pattern)
    }

    private func addAllRecommendedPatterns() {
        for pattern in missingRecommendedPatterns {
            addRecommendedPattern(pattern)
        }
    }
}

private struct FlowTags: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 6) {
                    Text(tag)
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(.quaternary)
                }
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 480
        let rows = rows(for: subviews, width: width)
        return CGSize(width: width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> (height: CGFloat, count: Int) {
        var x: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowCount = subviews.isEmpty ? 0 : 1

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
                rowCount += 1
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        totalHeight += rowHeight
        return (totalHeight, rowCount)
    }
}

import SearchCore
import SwiftUI

@main
struct NeedleApp: App {
    @NSApplicationDelegateAdaptor(NeedleAppDelegate.self) private var appDelegate
    @State private var model = SearchAppModel()
    @State private var shortcutController = GlobalShortcutController()

    var body: some Scene {
        WindowGroup {
            SearchWindow(model: model, shortcutController: shortcutController)
                .task {
                    NeedleAppDelegate.reopenHandler = {
                        shortcutController.showSearchWindow()
                    }
                    model.appSettings.launchAtLogin = LoginItemController.isEnabled
                    await model.start()
                    shortcutController.update(settings: model.appSettings)
                }
                .onChange(of: model.appSettings) { _, settings in
                    shortcutController.update(settings: settings)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("索引") {
                Button("重建索引") {
                    Task { await model.rebuildIndex() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Needle", systemImage: "magnifyingglass.circle") {
            Label(indexStatusText, systemImage: indexStatusIcon)

            Divider()

            Button("打开搜索窗口") {
                shortcutController.showSearchWindow()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("设置") {
                NeedleAppDelegate.settingsHandler?()
            }

            Divider()

            Button("重建索引") {
                Task { await model.rebuildIndex() }
            }
            .disabled(model.settings.roots.isEmpty)

            Button(model.appSettings.globalShortcutEnabled ? "关闭快捷键 ⌘⇧F" : "开启快捷键 ⌘⇧F") {
                model.appSettings.globalShortcutEnabled.toggle()
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var indexStatusText: String {
        switch model.state {
        case .idle:
            return "未开始索引"
        case .loading:
            return "正在加载索引"
        case .scanning(let processed):
            return "正在扫描 \(processed.formatted()) 项"
        case .watching:
            if model.indexNeedsRebuild {
                return "需要重建索引"
            }
            return "索引已就绪，\(model.records.count.formatted()) 个项目"
        case .permissionBlocked:
            return "部分目录无权限"
        case .degraded:
            return "索引异常"
        }
    }

    private var indexStatusIcon: String {
        switch model.state {
        case .watching:
            if model.indexNeedsRebuild {
                return "exclamationmark.arrow.triangle.2.circlepath"
            }
            return "checkmark.circle.fill"
        case .scanning:
            return "arrow.triangle.2.circlepath"
        case .permissionBlocked, .degraded:
            return "exclamationmark.triangle.fill"
        default:
            return "circle"
        }
    }
}

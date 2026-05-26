import SearchCore
import SwiftUI

struct PermissionGuideView: View {
    @Bindable var model: SearchAppModel
    @Binding var isPresented: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("开始使用 Needle")
                        .font(.largeTitle.bold())
                    Text("为了快速搜索本机文件，先完成三个基础设置。")
                        .foregroundStyle(.secondary)
                }
            }

            permissionRow(
                icon: "lock.open.display",
                title: "完全磁盘访问权限",
                description: "如果要搜索桌面、文稿、下载、照片资料库等位置，需要授予完全磁盘访问权限。已有 Needle 条目时打开开关即可；授权后请重启 Needle。",
                isComplete: model.permissionStatus.fullDiskAccessGranted,
                completeText: "已开启",
                incompleteText: "未确认",
                buttonTitle: "打开隐私设置",
                secondaryButtonTitle: "重启 Needle"
            ) {
                model.openPrivacySettings()
            } secondaryAction: {
                NeedleAppDelegate.relaunchCurrentApp()
            }

            permissionRow(
                icon: "keyboard.badge.eye",
                title: "辅助功能权限",
                description: "全局快捷键需要监听键盘事件。如果系统里显示已开启但这里仍未生效，请删除旧条目后重新添加 /Applications/Needle.app。",
                isComplete: model.permissionStatus.accessibilityGranted,
                completeText: "已开启",
                incompleteText: "未生效",
                buttonTitle: "打开辅助功能"
            ) {
                model.openAccessibilitySettings()
            }

            permissionRow(
                icon: "externaldrive.badge.checkmark",
                title: "选择索引范围",
                description: "建议先选择一个小目录测试，再逐步加入个人文件夹或外接磁盘。",
                isComplete: !model.settings.roots.isEmpty,
                completeText: "已选择",
                incompleteText: "未选择",
                buttonTitle: "打开设置"
            ) {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    onOpenSettings()
                }
            }

            permissionRow(
                icon: "arrow.down.circle",
                title: "自动检查更新",
                description: "Needle 会在后台检查新版本，只提示更新，不会自动下载。",
                isComplete: model.appSettings.autoCheckUpdates,
                completeText: "已开启",
                incompleteText: "未开启",
                buttonTitle: model.appSettings.autoCheckUpdates ? "关闭" : "开启"
            ) {
                model.appSettings.autoCheckUpdates.toggle()
            }

            HStack {
                Spacer()
                Button("稍后再说") {
                    model.completeOnboarding()
                    isPresented = false
                }
                Button("刷新状态") {
                    model.refreshPermissionStatus()
                }
                Button("完成") {
                    model.completeOnboarding()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 680)
    }

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        isComplete: Bool,
        completeText: String,
        incompleteText: String,
        buttonTitle: String,
        secondaryButtonTitle: String? = nil,
        action: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(isOn: isComplete, onText: completeText, offText: incompleteText)
            HStack(spacing: 8) {
                Button(buttonTitle, action: action)
                if let secondaryButtonTitle, let secondaryAction {
                    Button(secondaryButtonTitle, action: secondaryAction)
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

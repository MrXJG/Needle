import SearchCore
import SwiftUI

struct PermissionGuideView: View {
    @Bindable var model: SearchAppModel
    @Binding var isPresented: Bool

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
                icon: "externaldrive.badge.checkmark",
                title: "选择索引范围",
                description: "建议先选择一个小目录测试，再逐步加入个人文件夹或外接磁盘。",
                isComplete: !model.settings.roots.isEmpty,
                completeText: "已选择",
                incompleteText: "未选择",
                buttonTitle: "打开设置"
            ) {
                isPresented = false
            }

            permissionRow(
                icon: "lock.open.display",
                title: "完全磁盘访问权限",
                description: "如果要搜索桌面、文稿、下载、照片资料库等位置，需要授予完全磁盘访问权限。推荐方式是在系统设置列表中点击 +，选择 /Applications/Needle.app。",
                isComplete: model.permissionStatus.fullDiskAccessGranted,
                completeText: "已开启",
                incompleteText: "未确认",
                buttonTitle: "打开隐私设置"
            ) {
                model.openPrivacySettings()
            }

            permissionRow(
                icon: "keyboard.badge.eye",
                title: "辅助功能权限",
                description: "全局快捷键需要监听键盘事件。macOS 会要求你在辅助功能中允许本应用。",
                isComplete: model.permissionStatus.accessibilityGranted,
                completeText: "已开启",
                incompleteText: "未开启",
                buttonTitle: "打开辅助功能"
            ) {
                model.openAccessibilitySettings()
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
        action: @escaping () -> Void
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
            Button(buttonTitle, action: action)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

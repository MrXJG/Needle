# Needle

Needle 是一款原生 macOS 文件搜索工具，目标是在 macOS 上提供接近 Everything 的极速文件名搜索体验，同时保持 macOS 应用应有的轻量、克制和优雅。

第一版重点是“独立极速文件名索引 + 原生 macOS 交互体验”。Needle 不把 Spotlight 作为主搜索引擎，而是使用本地 SQLite 索引、初始目录扫描和 FSEvents 增量监听来维护搜索数据。

## 主要特性

- 原生 Swift / SwiftUI macOS 应用，默认中文界面。
- 独立 SQLite 文件名索引，不依赖 Spotlight 作为主搜索引擎。
- 支持文件名、路径、扩展名、通配符和正则搜索。
- 支持文件 / 文件夹过滤、大小和修改时间展示。
- 支持键盘优先操作、Quick Look 预览、Finder 中显示、复制路径和右键菜单。
- 支持 FSEvents 增量更新，新建、删除、移动、重命名文件后会自动更新索引。
- 设置页支持索引位置、排除项、隐藏文件、路径匹配、登录启动、全局快捷键和权限引导。
- 提供本地 `.app` 打包、DMG 生成和 Developer ID 公证脚本骨架。

## 当前状态

Needle 目前处于预览阶段，适合本地测试和功能打磨。当前发布包是本地 ad-hoc 签名版本，还不是 Developer ID 签名和 Apple notarization 公证后的正式发行包。

已完成的产品进度记录在 [PROGRESS.md](PROGRESS.md)，手动发布检查清单记录在 [docs/QA_CHECKLIST.md](docs/QA_CHECKLIST.md)。

## 构建与测试

```sh
swift build
swift test
swift run NeedleCoreCheck
swift run Needle
```

`NeedleCoreCheck` 是一个轻量烟雾测试入口，用于快速验证查询解析、排序、排除规则和 SQLite 持久化。`swift test` 会运行标准 XCTest 测试套件。

## 打包本地 App

```sh
scripts/package_app.sh debug
open .build/app/Needle.app
```

如果要测试完全磁盘访问、辅助功能权限、登录启动或全局快捷键，建议先安装到 `/Applications`。macOS 系统设置对“应用程序”文件夹里的 App 处理更稳定。

```sh
scripts/package_app.sh debug --install
open /Applications/Needle.app
```

打包脚本会构建 SwiftPM 可执行文件，组装标准 macOS `.app` Bundle，写入 `Info.plist`，复制应用图标，并对本地构建执行 ad-hoc 签名。

## 生成 DMG

```sh
scripts/create_dmg.sh release
open dist/Needle.dmg
```

如果要进行 Developer ID 签名，需要先提供签名身份：

```sh
export NEEDLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
scripts/create_dmg.sh release
```

如果要对已签名 DMG 做 Apple notarization，需要设置 Apple 公证凭据：

```sh
export NEEDLE_NOTARY_APPLE_ID="you@example.com"
export NEEDLE_NOTARY_TEAM_ID="TEAMID"
export NEEDLE_NOTARY_PASSWORD="app-specific-password"
scripts/notarize_dmg.sh dist/Needle.dmg
```

## 首次使用

Needle 默认不会自动扫描整个用户目录。首次启动后请进入设置页，先添加一个较小的常用目录并重建索引，确认速度和结果符合预期后再扩大索引范围。

如果需要搜索桌面、文稿、下载、照片图库等受保护目录，请在 macOS 系统设置中为 Needle 添加“完全磁盘访问”权限。权限引导会提示使用系统设置里的 `+` 按钮选择 `/Applications/Needle.app`。不把“拖拽 App 到权限列表”作为主要流程，是因为 macOS TCC 权限面板对自定义拖拽源的处理并不稳定。

全局快捷键需要辅助功能权限。默认快捷键是 `Command-Shift-F`。

## 设计方向

Needle 的目标不是简单复刻 Windows Everything 的界面，而是把“极快的文件名搜索”放进更符合 macOS 的交互里：

- 主窗口保持 Spotlight 式轻量搜索心智。
- 设置页采用覆盖式面板，减少独立窗口管理负担。
- 搜索结果强调键盘操作、快速预览和 Finder 工作流。
- 视觉上保持低噪声、清晰层级和原生 macOS 质感。

## 许可证

当前尚未选择正式开源许可证。发布前需要补充 `LICENSE`。

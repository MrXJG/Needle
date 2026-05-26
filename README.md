# Needle

Needle 是一款为 macOS 设计的原生文件搜索工具。它面向每天需要频繁定位文件、资料、项目目录和工作文档的用户，目标是在 macOS 上提供快速、稳定、低打扰的文件名搜索体验。

Needle 不依赖 Spotlight 作为主搜索引擎，而是在本机建立独立文件名索引。索引数据保存在本地 SQLite 中，搜索时加载到内存进行匹配和排序；文件系统变化通过 FSEvents 增量更新。它更适合“我知道文件大概叫什么，需要立刻找到它”的高频文件管理场景。

## 界面预览

![Needle 主搜索窗口](docs/images/needle-main-real.png)

![Needle 设置覆盖页](docs/images/needle-settings-real.png)

## 核心能力

- 原生 macOS 应用，使用 Swift / SwiftUI 构建，默认中文界面。
- 独立本地索引，不把 Spotlight 作为主搜索源。
- 支持文件名、路径、扩展名、通配符和正则搜索。
- 支持文件、文件夹筛选，以及名称、类型、大小、修改时间排序。
- 支持 FSEvents 增量更新，新建、删除、移动、重命名文件后会自动更新索引。
- 支持 Quick Look、Finder 中显示、打开方式、复制路径、复制名称、拖拽文件到其他 App。
- 右侧详情栏展示位置、大小、访问权限、创建时间、修改时间和可复制文本预览。
- 设置页支持索引位置、排除规则、隐藏文件、路径匹配、登录启动、全局快捷键、后台运行和权限引导。
- 冷启动采用分阶段索引加载，先显示可用界面，再在后台加载完整内存索引，减少启动卡顿。
- 后台运行时会释放前台全量索引资源，保留轻量状态，降低长时间驻留的资源占用。

## 搜索语法

Needle 默认会匹配文件名，也可以在设置或筛选中启用路径匹配。

常用输入示例：

```text
report
项目 文档
.swift
*.rpm
README*
re:^IMG_.*\.jpg$
ext:pdf 合同
```

说明：

- `.swift` 会按扩展名搜索 Swift 文件。
- `*.rpm`、`README*` 这类输入会作为通配符匹配。
- `re:` 前缀表示正则搜索，正则无效时界面会给出提示。
- 多个普通关键词会同时匹配，适合逐步缩小结果范围。

## 使用方式

首次启动后，进入设置页添加要索引的位置，然后执行一次重建索引。建议先添加常用工作目录，确认结果质量和性能后，再扩大到用户目录或外接磁盘。

如果要搜索桌面、文稿、下载、照片图库、部分应用数据等受保护目录，需要在 macOS 系统设置中为 Needle 授予“完全磁盘访问”权限。推荐方式是在系统设置的权限列表中点击 `+`，选择 `/Applications/Needle.app`。

全局快捷键默认是 `Command-Shift-F`。启用全局快捷键需要辅助功能权限，授权后可以在任何应用中快速唤起 Needle。

## 隐私与数据

Needle 的索引数据保存在本机，不上传文件名、路径或搜索内容。应用只索引你在设置中添加的位置，并会按排除规则跳过缓存、依赖目录和低价值噪声目录。

完全磁盘访问只用于读取你选择索引范围内的受保护目录；辅助功能权限只用于全局快捷键监听。

## 构建与测试

```sh
swift build
swift test
swift run NeedleCoreCheck
swift run Needle
```

`NeedleCoreCheck` 是轻量烟雾测试入口，用于验证查询解析、排序、排除规则和 SQLite 持久化。`swift test` 会运行完整 XCTest 测试套件。

## 本地安装

```sh
scripts/package_app.sh debug --install
open /Applications/Needle.app
```

打包脚本会构建 SwiftPM 可执行文件，组装标准 macOS `.app` Bundle，写入 `Info.plist`，复制应用图标，并对本地构建执行签名。测试完全磁盘访问、辅助功能权限、登录启动或全局快捷键时，建议使用 `/Applications/Needle.app`。

## 生成 DMG

```sh
scripts/create_dmg.sh release
open dist/Needle.dmg
```

Developer ID 签名：

```sh
export NEEDLE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
scripts/create_dmg.sh release
```

Apple notarization：

```sh
export NEEDLE_NOTARY_APPLE_ID="you@example.com"
export NEEDLE_NOTARY_TEAM_ID="TEAMID"
export NEEDLE_NOTARY_PASSWORD="app-specific-password"
scripts/notarize_dmg.sh dist/Needle.dmg
```

## 设计原则

Needle 不是把 Windows 工具直接搬到 macOS，而是把极速文件名搜索放进更符合 macOS 的工作流：

- 主窗口保持 Spotlight 式轻量心智，输入即搜。
- 结果列表优先支持键盘操作，也保留完整右键菜单。
- 详情栏服务于快速确认文件，而不是替代 Finder。
- 设置采用覆盖式面板，减少独立窗口管理负担。
- 视觉上保持低噪声、清晰层级和原生质感。

## 项目状态

Needle 已具备日常文件名搜索、索引管理、增量更新、权限引导、全局快捷键、后台运行、文本预览和 DMG 打包能力。后续重点会继续围绕大索引性能、Developer ID 正式签名发行、更多查询语法和异常索引恢复能力打磨。

产品进度记录在 [PROGRESS.md](PROGRESS.md)，发布检查清单记录在 [docs/QA_CHECKLIST.md](docs/QA_CHECKLIST.md)，更新记录见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

Needle 使用 [GNU Affero General Public License v3.0](LICENSE) 开源。

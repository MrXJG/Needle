# Needle 性能优化报告（2026-05-25）

## 目标
- 尽可能降低后台常驻 CPU 占用。
- 在不影响搜索正确性的前提下，降低重复搜索导致的 CPU 浪费。
- 保持后台内存卸载策略有效，并增强可观测性，便于后续持续优化。

## 本轮改动

### 1) 搜索去重（减少无效 CPU 消耗）
- 文件：`Sources/SearchCore/SearchAppModel.swift`
- 新增 `SearchContext`（`queryText + kindFilter + matchPath + recordsRevision`）作为搜索上下文签名。
- 新增 `lastCompletedSearchContext`，当上下文未变化时跳过重复搜索。
- 为避免误伤正确性，增加保护：
  - 若当前可见结果中存在已删除文件，**不跳过**搜索，继续触发“自愈清理”。

### 2) 后台可见性轮询降频（降低空转 CPU）
- 文件：`Sources/SearchCore/SearchAppModel.swift`
- 可见性巡检周期从 `5s` 调整为 `20s`，减少后台周期性唤醒。

### 3) 内存数据变更版本化（保障去重判定正确）
- 文件：`Sources/SearchCore/SearchAppModel.swift`
- 新增 `recordsRevision`，在索引加载、重建、增量合并、删除失效项、卸载等场景递增。
- 去重仅在“查询条件与数据版本都一致”时生效，避免旧结果误复用。

### 4) 新增性能可观测指标（用于诊断报告）
- 文件：`Sources/SearchCore/SearchAppModel.swift`
- 新增指标：
  - `executedSearchCount`
  - `skippedSearchCount`
- 已写入 `diagnosticsReport()` 输出，便于现场确认“节流是否生效”。

### 5) 回归测试补充
- 文件：`Tests/SearchCoreTests/SearchCoreTests.swift`
- 新增测试：
  - `testSearchSkipsRedundantRequestsWhenInputsUnchanged`
  - `testDefaultListDoesNotSelfHealIntoEmptyResultsFromMissingVisibleFiles`
- 验证点：
  - 相同查询重复触发时，`executedSearchCount` 不增长；
  - `skippedSearchCount` 增长，证明去重路径生效。
  - 默认列表不再因为可见文件瞬时不可达而被自愈逻辑清空。

### 6) 默认列表结果发布边界重构
- 文件：`Sources/SearchCore/SearchAppModel.swift`
- 根因：`fileExists` 自愈逻辑本来用于“显式搜索已删除文件”，但也作用在默认列表上。默认列表中的路径可能因为权限、缓存目录波动、文件系统事件时序而瞬时不可达，导致 `results` 被发布为空数组，界面表现为列表突然空白再恢复。
- 调整：
  - 默认列表（空查询 + 全部类型）不再逐条做 `fileExists` 自愈。
  - 显式搜索或筛选仍保留存在性校验，删除文件后仍能及时从结果中消失。
  - 已移除 UI 层“稳定结果缓存”补丁，把修复放回模型层。

### 7) 后台卸载与可见结果解耦
- 文件：`Sources/SearchCore/SearchAppModel.swift`
- 根因补充：后台卸载索引时把 `recordsStorage` 和 `results` 一起清空。如果窗口可见性事件被系统瞬时误判，UI 会直接收到空结果，表现为列表突然空白。
- 调整：
  - 后台卸载只释放全量索引 `recordsStorage`。
  - 保留当前最多 200 条 `results` 作为轻量可见快照。
  - 前台恢复时仍从 SQLite 重新加载完整索引并刷新结果。
- 这不是 UI 缓存补丁，而是把“全量索引内存”和“当前可见结果”拆成两个生命周期。

## 验证结果
- 本地执行：`swift test`
- 结果：`44` 个测试全部通过（含新增性能与默认列表稳定性回归测试）。
- 关键回归点（删除文件后结果应即时消失）已复测通过：
  - `testSearchFiltersOutDeletedFileBeforeRescanCompletes`
- 本地安装并启动 `/Applications/Needle.app` 后观察：
  - 25 秒后列表仍有行数据；
  - 约 60 秒后列表仍有行数据，没有复现“静置后空白”。

## 预期收益
- CPU：
  - 重复输入同一查询、或 UI 状态触发重复刷新时，搜索计算次数显著下降。
  - 后台空转轮询次数下降约 `75%`（5s -> 20s）。
- 内存：
  - 仍沿用后台卸载索引内存策略（清空 `recordsStorage` + `malloc_zone_pressure_relief`）。
  - 当前可见 `results` 最多约 200 条，保留它不会接近全量索引的内存成本，但能避免 UI 空白。
  - 本轮未改变内存模型结构（如索引压缩/分页），因此“峰值内存”不会出现结构性跳变，重点是“后台与空转成本”更稳。

## 额外发现
- 当索引范围包含整个个人目录时，`~/Library/Caches`、`~/Library/HTTPStorages`、`~/Library/Preferences`、`~/.hermes` 等目录会持续产生 FSEvents。
- 这些事件会触发连续增量 rescan，导致 CPU 周期性偏高。
- 这是后续需要单独处理的“事件风暴降噪”问题，和本次列表空白根因不同。

## 你可以如何复测（建议）
1. 启动 Needle，打开一个固定查询，重复触发同一查询若干次。
2. 导出诊断报告，重点看：
   - `Executed search count`
   - `Skipped search count`
3. 观察后台 CPU：
   - 隐藏窗口后，使用活动监视器查看 Needle 的 CPU 曲线应更平缓。
4. 观察后台内存：
   - 隐藏窗口后等待数秒，内存应回落到“UI + 运行时基线”，而非保留完整索引。

## 下一步优化建议（可继续推进）
- 索引结构降内存：将热字段与冷字段拆分，减少 `FileRecord` 常驻体积。
- 结果校验降 I/O：对 `fileExists` 做短周期缓存，降低频繁 `stat` 调用。
- 增量更新并行策略自适应：根据事件批量动态调整并发，抑制峰值 CPU 抖动。

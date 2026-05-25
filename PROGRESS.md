# Needle Progress

## Current Status
- Status: Prototype usable, active polishing.
- Last updated: 2026-05-25
- Build target: Native macOS 14+ SwiftUI app.
- Distribution target: Developer ID signed DMG later; current local builds use ad-hoc signing.

## Completed
- Native macOS search window with Chinese UI.
- Product icon uses the selected `10-index-layers` direction with committed PNG source and `.icns` bundle asset.
- SQLite-backed filename/path index independent from Spotlight.
- Initial directory scanning and basic FSEvents incremental updates.
- FSEvents handling detects dropped events, root changes, oversized batches, and watcher startup failure.
- Indexed roots are monitored for mount/unmount availability and reported when missing.
- Search by terms, quoted terms, `.ext`, `ext:ext`, wildcard patterns, and `re:` regex patterns.
- Search ranking prioritizes exact filename matches, filename-stem matches, prefix matches, path-only matches, recent opens, and user-selected root proximity.
- File/folder filters, path matching toggle, result sorting, right-click actions, open-with picker, Finder reveal, copy actions, drag support.
- Quick Look preview pane with inspector-style metadata and Space key Quick Look from the result list.
- Small text files can be previewed in a selectable/copyable text view inside the inspector pane.
- Settings overlay for permissions, behavior, indexed locations, exclusion rules, search behavior, rebuild, login launch, global shortcut, and background behavior.
- Settings sections use lighter native grouping with reduced nested card weight.
- Settings exclusion rules support custom entries plus one-click common exclusions such as `.build`, `node_modules`, `.git`, `Library/Caches`, and `DerivedData`.
- Settings clearly marks index-affecting changes that require rebuilding, and rebuild completion is shown temporarily in the main window and settings.
- Settings provides a diagnostics section for opening the log directory and exporting a support report.
- Diagnostics reports include search, rebuild, rescan, and FSEvents batch metrics.
- Preview pane now uses proportional default width and more compact metadata ordering.
- Menu bar/background running behavior with simplified status, open, settings, rebuild, shortcut, and quit actions.
- DMG packaging, Developer ID signing hooks, notarization script, and release QA checklist are available.

## Active Improvement Backlog

### P0 Reliability
- [x] Harden FSEvents indexing: detect dropped events, large move/delete batches, and failed watcher states.
- [x] Add mount/unmount handling for external disks and missing indexed roots.
- [x] Improve permission status accuracy for Full Disk Access and Accessibility.
- [x] Add lightweight app diagnostics for indexing/search latency and UI stalls.

### P1 Search Experience
- [x] Show a visible warning for invalid `re:` regular expressions instead of silently returning empty results.
- [x] Update Quick Look panel automatically when the selected result changes while the panel is open.
- [x] Add a compact visible search syntax hint for `.swift`, `*.rpm`, and `re:^IMG_.*\.jpg$`.
- [x] Improve ranking weights for exact filename matches, filename-stem matches, and open history.
- [x] Add true recent-open timestamp ranking and user-preferred folder boosts.

### P1 Index Management
- [x] Provide one-click common exclusions such as `.build`, `node_modules`, `.git`, `Library/Caches`, and derived-data-like folders.
- [x] Mark settings that require index rebuild more explicitly.
- [x] Add a post-rebuild completion state in both main window and settings for 3 seconds.

### P2 Product Polish
- [x] Refine preview pane spacing, separators, and metadata hierarchy.
- [x] Refine settings section density and reduce nested card weight.
- [x] Simplify menu bar actions to status, open window, settings, rebuild, shortcut toggle, and quit.
- [x] Add a crash/error log location and user-facing diagnostics export later.

### Release Readiness
- [x] Create DMG packaging flow.
- [x] Add Developer ID signing and notarization scripts. Actual notarization requires Apple credentials at release time.
- [x] Add first-run QA checklist for light/dark mode, permissions, shortcut, background running, Quick Look, Finder reveal, and large indexes.
- [x] Run large-index performance QA: 100k+ files, cold start, continuous typing, and rebuild.

## Verification Standard
- `swift build`
- `swift test`
- `swift run NeedleCoreCheck`
- `scripts/package_app.sh debug --install`
- `codesign --verify --deep --strict --verbose=2 /Applications/Needle.app`
- Manual smoke test on installed `/Applications/Needle.app`

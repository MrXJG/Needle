# Needle QA Checklist

## First Run
- Launch `/Applications/Needle.app`.
- Confirm the permission guide opens on first launch.
- Open Full Disk Access settings and verify the copy instructs adding Needle with the `+` button.
- Open Accessibility settings and verify the global shortcut permission guidance.
- Add a small folder as the first indexed root.
- Rebuild the index and confirm progress appears in both the main window and settings.
- Confirm the rebuild button shows `已完成索引` for about 3 seconds.

## Search
- Search a known filename.
- Search by extension with `.swift`.
- Search by wildcard with `*.rpm`.
- Search by regex with `re:^IMG_.*\.jpg$`.
- Enter an invalid regex such as `re:[` and confirm the orange warning appears.
- Toggle file/folder filters and path matching.

## Result Actions
- Use arrow keys to change selection.
- Press Return to open a result.
- Press Space to open Quick Look.
- Use the right-click menu to open with another app, reveal in Finder, copy path, copy filename, and open parent folder.
- Drag a result into Finder or another app.

## Settings
- Add and remove indexed folders.
- Remove a common exclusion and confirm the one-click common exclusion button appears.
- Change an index-affecting setting and confirm `需要重建` appears.
- Change `默认搜索路径` and confirm it does not require index rebuild.
- Export a diagnostics report and verify it appears in `Application Support/Needle/Logs`.

## Background Behavior
- Close the search window and confirm Needle remains available from the menu bar when background running is enabled.
- Toggle the global shortcut and test `Command-Shift-F`.
- Use the menu bar to open the window, open settings, rebuild, toggle shortcut, and quit.

## Visual QA
- Check light mode.
- Check dark mode.
- Confirm settings opens without blur, dimming, or janky motion.
- Confirm the preview pane metadata remains readable for long paths.

## Storage And Reliability
- Create, rename, move, and delete files under an indexed root and verify results update.
- Disconnect or rename an indexed external volume and confirm Needle reports the missing root.
- Reconnect the volume and confirm Needle resumes watching or rebuilds when needed.
- Run `swift run NeedleCoreCheck` and confirm the 100k-record search smoke check passes.

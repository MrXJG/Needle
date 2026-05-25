import AppKit
import SearchCore
import SwiftUI
import UniformTypeIdentifiers

struct FileIconView: View {
    enum Mode {
        case list
        case preview
    }

    let record: FileRecord
    var mode: Mode = .list
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: FileIconProvider.shared.icon(for: record, mode: mode))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

@MainActor
private final class FileIconProvider {
    static let shared = FileIconProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 768
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: .needleDidUnloadForegroundResources,
            object: nil
        )
    }

    func icon(for record: FileRecord, mode: FileIconView.Mode) -> NSImage {
        let cacheKey = key(for: record, mode: mode) as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let icon = makeIcon(for: record, mode: mode)
        cache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private func key(for record: FileRecord, mode: FileIconView.Mode) -> String {
        switch mode {
        case .preview:
            return "file:\(record.path)"
        case .list:
            if record.kind == .folder, record.ext == "app" {
                return "bundle:\(record.path)"
            }
            if record.kind == .folder {
                return "kind:folder"
            }
            if !record.ext.isEmpty {
                return "ext:\(record.ext)"
            }
            return "kind:\(record.kind.rawValue)"
        }
    }

    private func makeIcon(for record: FileRecord, mode: FileIconView.Mode) -> NSImage {
        if mode == .preview || record.ext == "app" {
            let pathIcon = NSWorkspace.shared.icon(forFile: record.path)
            if pathIcon.isValid {
                return pathIcon
            }
        }

        switch record.kind {
        case .folder:
            return NSWorkspace.shared.icon(for: .folder)
        case .file:
            if !record.ext.isEmpty {
                return NSWorkspace.shared.icon(for: contentType(for: record.ext, fallback: .data))
            }
            return NSWorkspace.shared.icon(for: .data)
        case .other:
            if !record.ext.isEmpty {
                return NSWorkspace.shared.icon(for: contentType(for: record.ext, fallback: .item))
            }
            return NSWorkspace.shared.icon(for: .item)
        }
    }

    private func contentType(for extensionName: String, fallback: UTType) -> UTType {
        UTType(filenameExtension: extensionName) ?? fallback
    }

    @objc private func clearCache() {
        cache.removeAllObjects()
    }
}

import CoreServices
import Foundation

public struct FSEventsUpdate: Sendable {
    public let paths: [String]
    public let requiresFullRescan: Bool
    public let reason: String?
}

public final class FSEventsWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (FSEventsUpdate) -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "needle.fsevents")
    private let handler: Handler
    private let largeBatchThreshold = 2_000

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    @discardableResult
    public func start(paths: [String]) -> Bool {
        stop()
        guard !paths.isEmpty else { return true }

        let callback: FSEventStreamCallback = { _, context, count, eventPaths, eventFlags, _ in
            guard let context else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(context).takeUnretainedValue()
            let pathsPointer = unsafeBitCast(eventPaths, to: NSArray.self)
            let paths = (0..<count).compactMap { index -> String? in
                pathsPointer[index] as? String
            }
            let flags = UnsafeBufferPointer(start: eventFlags, count: count)
            watcher.handler(watcher.makeUpdate(paths: paths, flags: Array(flags)))
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.75,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else {
            handler(FSEventsUpdate(paths: paths, requiresFullRescan: false, reason: "无法创建文件系统监听"))
            return false
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        let didStart = FSEventStreamStart(stream)
        if !didStart {
            handler(FSEventsUpdate(paths: paths, requiresFullRescan: false, reason: "无法启动文件系统监听"))
        }
        return didStart
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func makeUpdate(paths: [String], flags: [FSEventStreamEventFlags]) -> FSEventsUpdate {
        if paths.count >= largeBatchThreshold {
            return FSEventsUpdate(paths: paths, requiresFullRescan: true, reason: "文件系统事件过多")
        }

        let criticalFlags: [(FSEventStreamEventFlags, String)] = [
            (FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs), "事件丢失，需要重新扫描子目录"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped), "用户态事件丢失"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped), "内核事件丢失"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped), "事件编号已回绕"),
            (FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged), "监听根目录已变化")
        ]

        for flag in flags {
            for (criticalFlag, reason) in criticalFlags where flag & criticalFlag != 0 {
                return FSEventsUpdate(paths: paths, requiresFullRescan: true, reason: reason)
            }
        }

        return FSEventsUpdate(paths: paths, requiresFullRescan: false, reason: nil)
    }
}

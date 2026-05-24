import ApplicationServices
import Foundation

public struct PermissionStatus: Equatable, Sendable {
    public var fullDiskAccessGranted: Bool
    public var accessibilityGranted: Bool

    public init(
        fullDiskAccessGranted: Bool = false,
        accessibilityGranted: Bool = false
    ) {
        self.fullDiskAccessGranted = fullDiskAccessGranted
        self.accessibilityGranted = accessibilityGranted
    }
}

public enum PermissionStatusProvider {
    public static func current() -> PermissionStatus {
        PermissionStatus(
            fullDiskAccessGranted: canReadProtectedHomeLocation(),
            accessibilityGranted: AXIsProcessTrusted()
        )
    }

    private static func canReadProtectedHomeLocation() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Messages")
        ]

        return candidates.contains { url in
            canEnumerateDirectory(url)
        }
    }

    private static func canEnumerateDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        do {
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return true
        } catch {
            return false
        }
    }
}

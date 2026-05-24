import AppKit
import SwiftUI

struct AppActivationObserver: ViewModifier {
    let onActivate: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                onActivate()
            }
    }
}

extension View {
    func onAppActivate(_ action: @escaping () -> Void) -> some View {
        modifier(AppActivationObserver(onActivate: action))
    }
}

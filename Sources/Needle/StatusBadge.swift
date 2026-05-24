import SwiftUI

struct StatusBadge: View {
    let isOn: Bool
    let onText: String
    let offText: String

    var body: some View {
        Label(isOn ? onText : offText, systemImage: isOn ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(isOn ? .green : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }
}

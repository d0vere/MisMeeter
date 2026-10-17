import SwiftUI

extension View {
    func glassCard() -> some View {
        self.background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
                }
        }
    }
}

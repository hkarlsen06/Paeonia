import SwiftUI

extension View {
    /// A steady ring means only that the partner has this game open.
    /// Callers supply spoken presence separately from game progress.
    func gamePresenceRing(_ isHere: Bool) -> some View {
        overlay {
            Circle()
                .strokeBorder(.paeoniaSuccess, lineWidth: PaeoniaRadius.strokeEmphasis)
                .padding(-4)
                .opacity(isHere ? 1 : 0)
                .transaction { $0.animation = nil }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

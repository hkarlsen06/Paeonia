import SwiftUI

/// A small green dot that dims and brightens slowly, the sign that the partner has
/// the game open. Reduce Motion keeps it still.
struct GamePresenceDot: View {
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDim = false

    var body: some View {
        Circle()
            .fill(.paeoniaSuccess)
            .frame(width: size, height: size)
            .opacity(isDim ? 0.45 : 1)
            .scaleEffect(isDim ? 0.85 : 1)
            .animation(pulse, value: isDim)
            .onAppear { isDim = !reduceMotion }
            .accessibilityHidden(true)
    }

    private var pulse: Animation? {
        reduceMotion ? nil : PaeoniaMotion.standardCurve(duration: 1.2).repeatForever(autoreverses: true)
    }
}

extension View {
    /// The green dot at the top trailing edge of the partner's avatar while they
    /// have the game open.
    func gamePresenceDot(_ isHere: Bool, size: CGFloat) -> some View {
        overlay(alignment: .topTrailing) {
            if isHere {
                GamePresenceDot(size: size)
                    .overlay {
                        Circle().strokeBorder(.paeoniaBackgroundSecondary, lineWidth: PaeoniaRadius.strokeEmphasis)
                    }
                    .offset(x: size / 6, y: -size / 6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

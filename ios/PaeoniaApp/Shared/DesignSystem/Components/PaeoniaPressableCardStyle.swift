import SwiftUI

/// Press feel for a tappable card or row. The label shrinks a little while a finger is down
/// and springs back. Under Reduce Motion it stays the same size. There is no haptic, since a
/// finger resting on a card before a scroll would fire it. The style adds no background, so
/// the card keeps its own look. Apply it with `.buttonStyle(.paeoniaPressableCard)`.
struct PaeoniaPressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pressedScale: CGFloat

    init(pressedScale: CGFloat = 0.97) {
        self.pressedScale = pressedScale
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .animation(
                reduceMotion ? nil : .spring(duration: PaeoniaMotion.motionDefault, bounce: 0.3),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == PaeoniaPressableCardStyle {
    static var paeoniaPressableCard: PaeoniaPressableCardStyle { PaeoniaPressableCardStyle() }

    /// For a row inside a card, which has less to shrink than a whole card.
    static var paeoniaPressableRow: PaeoniaPressableCardStyle { PaeoniaPressableCardStyle(pressedScale: 0.98) }
}

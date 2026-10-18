import SwiftUI

/// Glides a board to a new size and place, such as when the result panel takes
/// room under it, instead of letting it jump. The board is laid out at its new
/// frame at once and drawn scaled from the old one, so its pieces, lines and
/// petals move together as one picture. The boards are square and fit their
/// slot, so the shorter side of the slot is the board's size. A row that only
/// moves glides without scaling.
struct BoardGameGlide: ViewModifier {
    /// The fixed column, which a navigation push or the keyboard doesn't move.
    nonisolated static let space = "boardGameGlide"

    let isEnabled: Bool
    var scales = true
    /// A move that comes with a change of this value animates itself and doesn't glide.
    var key: AnyHashable = 0

    @State private var frame: CGRect?
    @State private var lastKey: AnyHashable?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            // Measured outside the scale and offset, which only move the drawing.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { new in
                let sameKey = lastKey == key
                defer {
                    frame = new
                    lastKey = key
                }
                let side = min(new.width, new.height)
                guard isEnabled, sameKey, let old = frame, old != new, side > 0 else { return }
                var jump = Transaction()
                jump.disablesAnimations = true
                withTransaction(jump) {
                    scale = scales ? min(old.width, old.height) / side : 1
                    offset = CGSize(width: old.midX - new.midX, height: old.midY - new.midY)
                }
                withAnimation(PaeoniaMotion.meaningfulMoment) {
                    scale = 1
                    offset = .zero
                }
            }
    }
}

/// Hands its content the space a board that bleeds fits in. It is animatable, so
/// when that space changes, the content is laid out again on every frame of the
/// animation. The board's view and its camera then follow the space smoothly
/// instead of jumping to the end.
struct BoardGameAnimatedSlot<Content: View>: View, Animatable {
    var slot: CGRect
    @ViewBuilder let content: (CGRect) -> Content

    var animatableData: CGRect.AnimatableData {
        get { slot.animatableData }
        set { slot.animatableData = newValue }
    }

    var body: some View {
        content(slot)
    }
}

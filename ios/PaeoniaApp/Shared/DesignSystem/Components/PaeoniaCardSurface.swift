import SwiftUI

extension View {
    /// The shared card edge and pink glow while content waits for this person.
    func paeoniaCardSurface<S: InsettableShape, Fill: ShapeStyle>(
        in shape: S,
        fill: Fill,
        needsAttention: Bool = false
    ) -> some View {
        background {
            shape
                .fill(fill)
                .shadow(color: .paeoniaAccentPrimary.opacity(needsAttention ? 0.25 : 0), radius: 18, y: 6)
        }
        .overlay {
            shape.strokeBorder(
                needsAttention ? Color.paeoniaAccentPrimary.opacity(0.6) : .paeoniaSurfacePressed,
                lineWidth: needsAttention ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
            )
        }
    }
}

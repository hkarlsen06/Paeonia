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
                needsAttention ? Color.paeoniaAccentPrimary.opacity(0.6) : .paeoniaBorder,
                lineWidth: needsAttention ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeHairline
            )
        }
    }

    /// The plum tile of `PaeoniaCard` and the drawing widget: the page's own color, a thin edge
    /// and a soft shadow, or a pink edge and glow while content waits for this person.
    func paeoniaTileSurface(needsAttention: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)

        return background(.paeoniaBackgroundPrimary)
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    needsAttention ? Color.paeoniaAccentPrimary.opacity(0.6) : .paeoniaBorder,
                    lineWidth: needsAttention ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
                )
            }
            .shadow(
                color: needsAttention ? .paeoniaAccentPrimary.opacity(0.25) : .black.opacity(0.25),
                radius: 18,
                x: 0,
                y: needsAttention ? 6 : 10
            )
    }
}

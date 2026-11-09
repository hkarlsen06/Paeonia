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

    /// The plum tile of the Us tab's cards and the drawing widget: the page's own color, a thin
    /// edge and a soft shadow.
    func paeoniaTileSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)

        return background(.paeoniaBackgroundPrimary)
            .clipShape(shape)
            .overlay {
                shape.stroke(.paeoniaBorder, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }
}

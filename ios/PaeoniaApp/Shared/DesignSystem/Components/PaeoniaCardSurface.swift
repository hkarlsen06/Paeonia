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

    /// The plum tile of `PaeoniaCard` and the drawing widget, in one of its tones.
    func paeoniaTileSurface(_ tone: PaeoniaTileTone = .plain) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)

        return background(.paeoniaBackgroundPrimary)
            .clipShape(shape)
            .overlay { shape.stroke(tone.edge, lineWidth: tone.edgeWidth) }
            .shadow(color: tone.shadow, radius: 18, x: 0, y: tone == .plain ? 10 : 6)
    }
}

/// How a plum tile's edge and shadow look for what it holds. The fill is always the page's
/// plum: a whole card in another hue looks out of place, so the color stays in the edge.
enum PaeoniaTileTone: Equatable {
    /// A thin edge and a soft shadow.
    case plain
    /// A pink edge and glow while content waits for this person.
    case attention
    /// A lavender edge and glow, like the daily card's wax seal, for something the partner
    /// left that opens once this person answers too.
    case partnerWaiting

    /// The edge's color, and the glow's at a lower opacity.
    var tint: Color? {
        switch self {
        case .plain: nil
        case .attention: .paeoniaAccentPrimary
        case .partnerWaiting: .paeoniaInkLavender
        }
    }

    var edge: Color { tint?.opacity(0.6) ?? .paeoniaBorder }

    var edgeWidth: CGFloat { tint == nil ? PaeoniaRadius.strokeDefault : PaeoniaRadius.strokeEmphasis }

    var shadow: Color { tint?.opacity(0.25) ?? .black.opacity(0.25) }
}

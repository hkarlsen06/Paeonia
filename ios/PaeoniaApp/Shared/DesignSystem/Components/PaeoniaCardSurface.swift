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

        return background(tone.fill)
            .clipShape(shape)
            .overlay { shape.stroke(tone.edge, lineWidth: tone.edgeWidth) }
            .shadow(color: tone.shadow, radius: 18, x: 0, y: tone == .attention ? 6 : 10)
    }
}

/// How a plum tile looks for what it holds.
enum PaeoniaTileTone: Equatable {
    /// The page's own color, a thin edge and a soft shadow.
    case plain
    /// A pink edge and glow while content waits for this person.
    case attention
    /// Lavender, like the daily card's wax seal, for something the partner left that opens
    /// once this person answers too.
    case partnerWaiting

    var fill: Color {
        switch self {
        case .plain, .attention: .paeoniaBackgroundPrimary
        case .partnerWaiting: Color.paeoniaBackgroundPrimary.mix(with: .paeoniaInkLavender, by: 0.16)
        }
    }

    var edge: Color {
        switch self {
        case .plain: .paeoniaBorder
        case .attention: Color.paeoniaAccentPrimary.opacity(0.6)
        case .partnerWaiting: Color.paeoniaInkLavender.opacity(0.4)
        }
    }

    var edgeWidth: CGFloat {
        self == .attention ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
    }

    var shadow: Color {
        self == .attention ? Color.paeoniaAccentPrimary.opacity(0.25) : .black.opacity(0.25)
    }
}

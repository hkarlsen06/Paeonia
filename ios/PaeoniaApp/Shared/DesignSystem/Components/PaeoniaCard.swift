import SwiftUI

struct PaeoniaCard<Content: View>: View {
    enum Surface {
        /// The plum tile with a thin edge and a soft shadow, the same as the drawing widget's
        /// (`paeoniaTileSurface`).
        case tile
        /// The tile in lavender, for something the partner left that opens once this person
        /// answers too (`PaeoniaTileTone.partnerWaiting`).
        case partnerWaiting
        /// The raised plum fill of `PaeoniaGroupedList` rows, for cards on settings screens
        /// that sit beside those lists.
        case raised
    }

    private let content: Content
    private let padding: CGFloat
    private let surface: Surface

    init(
        padding: CGFloat = PaeoniaSpacing.cardContentPadding,
        surface: Surface = .tile,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
        self.surface = surface
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous)
        let padded = content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)

        switch surface {
        case .tile:
            padded.paeoniaTileSurface()
        case .partnerWaiting:
            padded.paeoniaTileSurface(.partnerWaiting)
        case .raised:
            padded
                .clipShape(shape)
                .paeoniaCardSurface(in: shape, fill: Color.paeoniaSurfacePrimary)
        }
    }
}

import SwiftUI

struct PaeoniaCard<Content: View>: View {
    enum Surface {
        /// The raised plum fill that matches `PaeoniaGroupedList` rows.
        case raised
        /// The Us tab's tile, the same as the drawing widget's (`paeoniaTileSurface`).
        case tile
    }

    private let content: Content
    private let padding: CGFloat
    private let surface: Surface

    init(
        padding: CGFloat = PaeoniaSpacing.cardContentPadding,
        surface: Surface = .raised,
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
        case .raised:
            padded
                .clipShape(shape)
                .paeoniaCardSurface(in: shape, fill: Color.paeoniaSurfacePrimary)
        case .tile:
            padded.paeoniaTileSurface()
        }
    }
}

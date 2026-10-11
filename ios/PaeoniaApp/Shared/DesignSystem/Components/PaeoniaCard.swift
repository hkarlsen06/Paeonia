import SwiftUI

struct PaeoniaCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(
        padding: CGFloat = PaeoniaSpacing.cardContentPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.paeoniaSurfacePrimary)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeHairline)
            }
    }
}

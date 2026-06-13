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
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.paeoniaSurfacePrimary)
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeHairline)
            }
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous))
    }
}

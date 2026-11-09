import SwiftUI

struct PaeoniaBannerSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
        if reduceTransparency || contrast == .increased {
            content.background(Color(uiColor: .secondarySystemBackground), in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

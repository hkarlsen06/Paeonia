import SwiftUI

struct PaeoniaBannerSurface: ViewModifier {
    let accent: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
        if reduceTransparency || contrast == .increased {
            content.background(.paeoniaBackgroundSecondary, in: shape)
        } else {
            content.glassEffect(.regular.tint(accent.opacity(0.16)), in: shape)
        }
    }
}

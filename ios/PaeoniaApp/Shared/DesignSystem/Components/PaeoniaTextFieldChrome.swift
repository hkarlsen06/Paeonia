import SwiftUI

extension View {
    @ViewBuilder
    func paeoniaTextFieldChrome(
        isFocused: Bool,
        accent: Color = .paeoniaAccentPrimary,
        isEmbedded: Bool = false
    ) -> some View {
        if isEmbedded {
            self
        } else {
            let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
            padding(PaeoniaSpacing.space12)
                .background(.paeoniaBackgroundSecondary, in: shape)
                .clipShape(shape)
                .overlay {
                    shape.stroke(
                        isFocused ? accent : .paeoniaBorder,
                        lineWidth: isFocused ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
                    )
                }
        }
    }
}

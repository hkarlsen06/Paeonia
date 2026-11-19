import SwiftUI

extension View {
    /// The box around a text field. The text field only takes taps on its lines of text, so
    /// a one-line field is about 22 points tall. A tap elsewhere in the box, or within 44
    /// points for an embedded field, calls `focus`. The tap sits behind the field, so a tap
    /// on the text still places the caret.
    @ViewBuilder
    func paeoniaTextFieldChrome(
        isFocused: Bool,
        accent: Color = .paeoniaAccentPrimary,
        isEmbedded: Bool = false,
        focus: @escaping () -> Void
    ) -> some View {
        if isEmbedded {
            frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: focus)
                }
        } else {
            let shape = RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
            padding(PaeoniaSpacing.space12)
                .background {
                    shape.fill(.paeoniaBackgroundSecondary)
                        .onTapGesture(perform: focus)
                }
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

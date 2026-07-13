import SwiftUI

struct PrivacySafetyMultilineField: View {
    @Binding var text: String
    let placeholder: LocalizedStringResource
    var lineLimit: ClosedRange<Int> = 3...7

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(
            text: $text,
            prompt: Text(placeholder),
            axis: .vertical
        ) {
            Text(placeholder)
        }
        .lineLimit(lineLimit)
        .font(PaeoniaTypography.body)
        .foregroundStyle(.paeoniaTextPrimary)
        .padding(PaeoniaSpacing.space12)
        .focused($isFocused)
        .background(.paeoniaBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
                .stroke(
                    isFocused ? Color.paeoniaAccentPrimary : Color.paeoniaSurfacePressed,
                    lineWidth: isFocused ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
                )
        }
        .animation(PaeoniaMotion.stateChange, value: isFocused)
    }
}

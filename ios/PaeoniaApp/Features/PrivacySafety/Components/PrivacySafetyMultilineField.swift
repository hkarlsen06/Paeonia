import SwiftUI

struct PrivacySafetyMultilineField: View {
    @Binding var text: String
    /// The visible label above the field. VoiceOver reads it instead of the placeholder.
    let label: LocalizedStringResource
    let placeholder: LocalizedStringResource
    var lineLimit: ClosedRange<Int> = 3...7
    var characterLimit = 4_000

    @FocusState private var isFocused: Bool

    private static let counterThreshold = 200

    private var charactersLeft: Int {
        max(characterLimit - text.count, 0)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: PaeoniaSpacing.space4) {
            field

            if charactersLeft <= Self.counterThreshold {
                Text(.privacySafetyFieldCharactersLeft(charactersLeft.formatted()))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(charactersLeft == 0 ? .paeoniaError : .paeoniaTextSecondary)
            }
        }
        .onChange(of: text) { _, newValue in
            if newValue.count > characterLimit {
                text = String(newValue.prefix(characterLimit))
            }
        }
    }

    private var field: some View {
        TextField(
            text: $text,
            prompt: Text(placeholder),
            axis: .vertical
        ) {
            Text(label)
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
        .accessibilityLabel(Text(label))
    }
}

import SwiftUI

/// A growing text field. Embedded fields share their surrounding composer's surface.
struct DailyAnswerTextField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var label: LocalizedStringResource = .dailyChallengeTextAnswerLabel
    var placeholder: LocalizedStringResource = .dailyChallengeTextAnswerPlaceholder
    var limit = DailyAnswerDraft.maxTextLength
    var isEmbedded = false

    @Environment(\.dailyAnswerComposerColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if !isEmbedded {
                HStack {
                    Text(label)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(colors.secondary)
                    Spacer(minLength: PaeoniaSpacing.space8)
                    characterCount
                }
            }

            field

            if isEmbedded {
                characterCount.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var field: some View {
        TextField(
            text: $text,
            prompt: Text(placeholder).foregroundStyle(colors.secondary),
            axis: .vertical
        ) {
            Text(label)
        }
        .lineLimit(isEmbedded ? 2...4 : 3...8)
        .font(PaeoniaTypography.body)
        .foregroundStyle(colors.foreground)
        .tint(colors.accent)
        .padding(isEmbedded ? 0 : PaeoniaSpacing.space12)
        .focused(isFocused)
        .accessibilityIdentifier("daily.answer.text")
        .background(isEmbedded ? Color.clear : Color.paeoniaBackgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
        .overlay {
            if !isEmbedded {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius12)
                    .stroke(
                        isFocused.wrappedValue ? colors.accent : Color.paeoniaSurfacePressed,
                        lineWidth: isFocused.wrappedValue
                            ? PaeoniaRadius.strokeEmphasis : PaeoniaRadius.strokeDefault
                    )
            }
        }
    }

    @ViewBuilder
    private var characterCount: some View {
        let length = DailyAnswerDraft.measuredLength(of: text)
        if length > limit - min(200, limit / 4) {
            Text(verbatim: "\(length.formatted()) / \(limit.formatted())")
                .font(PaeoniaTypography.caption.monospacedDigit())
                .foregroundStyle(length > limit ? Color.paeoniaError : colors.secondary)
                .accessibilityLabel(Text(.dailyChallengeTextAnswerCharacterCount(length, limit)))
        }
    }
}

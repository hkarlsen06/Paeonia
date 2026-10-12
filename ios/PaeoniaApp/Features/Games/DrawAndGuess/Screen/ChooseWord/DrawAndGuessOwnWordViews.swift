import SwiftUI

/// The "Draw your own" row, before the player taps it.
struct DrawAndGuessOwnWordRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PaeoniaSpacing.space12) {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(.gamesDrawAndGuessChooseOwnTitle)
                        .font(PaeoniaTypography.title)
                        .foregroundStyle(.paeoniaTextPrimary)
                    Text(.gamesDrawAndGuessChooseOwnSubtitle)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: PaeoniaSpacing.space8)
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)
            }
            .padding(PaeoniaSpacing.cardContentPadding)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(.paeoniaSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("draw.choose.own")
    }
}

/// The text field for a word of the player's own, with its counter and its message.
struct DrawAndGuessOwnWordField: View {
    @Bindable var viewModel: DrawAndGuessViewModel
    @Binding var showsTooShort: Bool
    @Binding var isWritingOwn: Bool
    var isFieldFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            fieldRow
            messageRow
        }
    }

    private var fieldRow: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            TextField(text: $viewModel.customWord) {
                Text(.gamesDrawAndGuessChooseOwnPlaceholder)
            }
            .font(PaeoniaTypography.title)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused(isFieldFocused)
            .onSubmit {
                if case .invalid(.tooShort) = viewModel.customWordValidation {
                    showsTooShort = true
                    PaeoniaHaptics.validationError()
                }
            }
            .accessibilityIdentifier("draw.custom.field")

            Button {
                isWritingOwn = false
                isFieldFocused.wrappedValue = false
                showsTooShort = false
                viewModel.customWord = ""
            } label: {
                Text(.commonCancel)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
        }
        .padding(.leading, PaeoniaSpacing.cardContentPadding)
        .padding(.trailing, PaeoniaSpacing.space4)
        .frame(minHeight: 64)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
                .strokeBorder(.paeoniaAccentPrimary, lineWidth: PaeoniaRadius.strokeEmphasis)
        }
    }

    private var messageRow: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space8) {
            if let message = shownMessage {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                }
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaErrorText)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            letterCounter
        }
        .padding(.horizontal, PaeoniaSpacing.space4)
    }

    private var letterCounter: some View {
        let count = viewModel.customWord.filter { !$0.isWhitespace }.count
        let limit = DrawAndGuessCustomWord.letterRange.upperBound
        return Text(.gamesDrawAndGuessChooseLetterCount(count, limit))
            .font(PaeoniaTypography.caption)
            .monospacedDigit()
            .foregroundStyle(count > limit ? .paeoniaErrorText : .paeoniaTextTertiary)
            .accessibilityLabel(Text(.gamesDrawAndGuessChooseLetterCountA11Y(count, limit)))
    }

    /// Too short shows only after Done, because every word starts too short.
    private var shownMessage: LocalizedStringResource? {
        guard case let .invalid(failure) = viewModel.customWordValidation else { return nil }
        if failure == .tooShort, !showsTooShort { return nil }
        return Self.message(for: failure)
    }

    static func message(for failure: DrawAndGuessCustomWord.Failure) -> LocalizedStringResource {
        switch failure {
        case .tooShort: .gamesDrawAndGuessChooseErrorTooShort
        case .tooLong: .gamesDrawAndGuessChooseErrorTooLong
        case .tooManyWords: .gamesDrawAndGuessChooseErrorTooManyWords
        case .notAllowedCharacter: .gamesDrawAndGuessChooseErrorCharacter
        }
    }
}

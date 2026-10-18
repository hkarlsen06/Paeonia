import SwiftUI

/// Pick one of three topics, or write your own, then "Start". Nothing is sent
/// until the marker is locked in, so this works offline once the topics are here.
struct ConsensioChooseView: View {
    @Bindable var viewModel: ConsensioViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?

    private enum Field {
        case subject, left, right
    }

    var body: some View {
        GameFocusedLayout(barRidesKeyboard: viewModel.isWritingOwn) {
            VStack(spacing: PaeoniaSpacing.space20) {
                heading
                if !viewModel.isWritingOwn {
                    rows
                        .transition(.opacity)
                }
                ownTopic
            }
            .frame(maxWidth: .infinity)
        } bottom: {
            Button {
                if viewModel.startPlacing() {
                    PaeoniaHaptics.selection()
                    GameSound.tap.play()
                    focusedField = nil
                } else {
                    PaeoniaHaptics.validationError()
                    GameSound.wrong.play(volume: 0.5)
                }
            } label: {
                Text(.consensioChooseStart)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(!viewModel.canStart)
            .accessibilityIdentifier("consensio.choose.start")
        }
        .gameInviteToolbar(
            invite: viewModel.invite,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "consensio.invite"
        )
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.stateChange, value: viewModel.isWritingOwn)
        .accessibilityIdentifier("consensio.choose")
    }

    private var heading: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(.consensioChooseTitle)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(viewModel.isFirstTurn
                ? .consensioChooseSubtitleFirst(viewModel.partnerName)
                : .consensioChooseSubtitle(viewModel.partnerName))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        if viewModel.choices.isEmpty {
            PaeoniaEmptyStateView(
                title: .consensioChooseOfflineTitle,
                message: .consensioChooseOfflineMessage,
                systemImage: "hourglass"
            ) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .accessibilityIdentifier("consensio.choose.retry")
            }
        } else {
            VStack(spacing: PaeoniaSpacing.space12) {
                ForEach(viewModel.choices, id: \.self) { topic in
                    row(for: .catalog(topic))
                }
            }
        }
    }

    private func row(for choice: ConsensioTopicChoice) -> some View {
        let isSelected = viewModel.selectedChoice == choice
        return Button {
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.7)
            viewModel.select(choice)
        } label: {
            ConsensioTopicRow(choice: choice, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .animation(PaeoniaMotion.buttonPress, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.consensioChooseRowA11Y(
            choice.subject,
            ConsensioEndText.inSentence(choice.leftEnd),
            ConsensioEndText.inSentence(choice.rightEnd)
        )))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("consensio.choose.row")
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
    }

    // MARK: Write your own

    @ViewBuilder
    private var ownTopic: some View {
        if viewModel.isWritingOwn {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                HStack {
                    Text(.consensioChooseOwnTitle)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                    Spacer()
                    Button {
                        viewModel.closeOwnTopic()
                        focusedField = nil
                    } label: {
                        Text(.commonCancel)
                    }
                    .buttonStyle(PaeoniaQuietButtonStyle())
                    .accessibilityIdentifier("consensio.own.cancel")
                }
                field(.consensioChooseOwnSubject, text: $viewModel.ownSubject, field: .subject)
                HStack(spacing: PaeoniaSpacing.space12) {
                    field(.consensioChooseOwnLeft, text: $viewModel.ownLeftEnd, field: .left)
                    field(.consensioChooseOwnRight, text: $viewModel.ownRightEnd, field: .right)
                }
                if let issue = viewModel.ownTopicIssue, focusedField == nil || issue != .subject && issue != .end {
                    Label {
                        Text(issue.message)
                    } icon: {
                        Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
                    }
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaErrorText)
                    .transition(.opacity)
                    .accessibilityIdentifier("consensio.own.issue")
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                focusedField = .subject
            }
        } else {
            Button {
                PaeoniaHaptics.selection()
                GameSound.tap.play(volume: 0.7)
                viewModel.openOwnTopic()
            } label: {
                HStack(spacing: PaeoniaSpacing.space12) {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                        Text(.consensioChooseOwnTitle)
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)
                        Text(.consensioChooseOwnSubtitle)
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(PaeoniaSpacing.space16)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(.paeoniaSurfaceSecondary, in: rowShape)
                .contentShape(rowShape)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("consensio.own.open")
        }
    }

    private func field(_ placeholder: LocalizedStringResource, text: Binding<String>, field: Field) -> some View {
        TextField(text: text) {
            Text(placeholder)
        }
        .font(PaeoniaTypography.body)
        .submitLabel(field == .right ? .done : .next)
        .focused($focusedField, equals: field)
        .onSubmit {
            switch field {
            case .subject: focusedField = .left
            case .left: focusedField = .right
            case .right: focusedField = nil
            }
        }
        .padding(.horizontal, PaeoniaSpacing.space12)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            .paeoniaSurfaceSecondary,
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
        )
    }
}

extension ConsensioTopicIssue {
    var message: LocalizedStringResource {
        switch self {
        case .subject: .consensioChooseOwnErrorSubject
        case .end: .consensioChooseOwnErrorEnd
        case .sameEnds: .consensioChooseOwnErrorSame
        case .characters: .consensioChooseOwnErrorCharacters
        }
    }
}

/// One topic on the list: its subject, and its two ends joined by an arrow.
private struct ConsensioTopicRow: View {
    let choice: ConsensioTopicChoice
    let isSelected: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
    }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(verbatim: choice.subject)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                HStack(spacing: PaeoniaSpacing.space4) {
                    Text(verbatim: choice.leftEnd)
                    Image(systemName: "arrow.left.and.right")
                        .font(.caption2)
                        .foregroundStyle(.paeoniaTextTertiary)
                        .accessibilityHidden(true)
                    Text(verbatim: choice.rightEnd)
                }
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .padding(PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(.paeoniaSurfaceSecondary, in: shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? Color.paeoniaAccentPrimary : .clear,
                lineWidth: PaeoniaRadius.strokeEmphasis
            )
        }
        .contentShape(shape)
    }
}

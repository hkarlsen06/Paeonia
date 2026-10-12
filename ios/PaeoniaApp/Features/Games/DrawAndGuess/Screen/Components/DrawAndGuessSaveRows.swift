import SwiftUI

/// The "Save this drawing to Memories?" row on the reveal. It turns into
/// "Saved to Memories" once a save went through.
struct DrawAndGuessSaveRow: View {
    let viewModel: DrawAndGuessViewModel
    @State private var isSavingFromHere = false

    var body: some View {
        Group {
            switch viewModel.savePrompt {
            case .hidden:
                EmptyView()
            case .ask, .saving:
                VStack(spacing: PaeoniaSpacing.space12) {
                    Text(.gamesDrawAndGuessSavePrompt)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                    buttons
                    if viewModel.savePrompt == .saving, viewModel.isWaitingToSend {
                        DrawAndGuessOfflineLine()
                    }
                }
            case .saved:
                saved(Text(.gamesDrawAndGuessSaveSaved))
            case .savedByPartner:
                saved(Text(.gamesDrawAndGuessSaveSavedBy(viewModel.partnerName)))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(PaeoniaMotion.stateChange, value: viewModel.savePrompt)
        .onChange(of: viewModel.savePrompt) { old, new in
            if new == .saved, old == .ask || old == .saving {
                PaeoniaHaptics.memorySaved()
            }
        }
        .accessibilityIdentifier("draw.save")
    }

    private var buttons: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Button {
                Task { await viewModel.skipSaving() }
            } label: {
                Text(.gamesDrawAndGuessSaveNotNow)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .disabled(viewModel.savePrompt == .saving)
            .accessibilityIdentifier("draw.save.notNow")

            Button {
                Task { await viewModel.saveToMemories() }
            } label: {
                Text(.gamesDrawAndGuessSaveSave)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: viewModel.savePrompt == .saving))
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("draw.save.yes")
        }
    }

    private func saved(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.bodyEmphasis)
        .foregroundStyle(.paeoniaSuccess)
        .transition(.opacity)
        .accessibilityIdentifier("draw.save.saved")
    }
}

/// "Saved on this phone. We'll send it when you're online."
struct DrawAndGuessOfflineLine: View {
    var body: some View {
        Label {
            Text(.gamesPendingSavedOnPhone)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "clock")
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption)
        .foregroundStyle(.paeoniaSyncPending)
        .accessibilityIdentifier("draw.pending")
    }
}

/// The save question that waits at the top of the choose and waiting screens
/// when the player left the result without answering.
struct DrawAndGuessPendingSaveRow: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        if viewModel.savePrompt != .hidden, let round = viewModel.round {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                HStack(spacing: PaeoniaSpacing.space12) {
                    DrawAndGuessThumbnail(drawing: viewModel.finalDrawing)
                    switch viewModel.savePrompt {
                    case .saved:
                        Label {
                            Text(.gamesDrawAndGuessSaveSaved)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                        }
                        .foregroundStyle(.paeoniaSuccess)
                    case .savedByPartner:
                        Text(.gamesDrawAndGuessSaveSavedBy(viewModel.partnerName))
                            .foregroundStyle(.paeoniaTextPrimary)
                    default:
                        Text(.gamesDrawAndGuessSavePendingRow(DrawAndGuessAnswer.display(round.word)))
                            .foregroundStyle(.paeoniaTextPrimary)
                    }
                    Spacer(minLength: 0)
                }
                .font(PaeoniaTypography.bodyEmphasis)
                if viewModel.savePrompt == .ask || viewModel.savePrompt == .saving {
                    DrawAndGuessSaveRowButtons(viewModel: viewModel)
                }
            }
            .padding(PaeoniaSpacing.space12)
            .background(.paeoniaSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("draw.save.pending")
        }
    }
}

/// Not now and Save, as two equal buttons.
private struct DrawAndGuessSaveRowButtons: View {
    let viewModel: DrawAndGuessViewModel

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            Button {
                Task { await viewModel.skipSaving() }
            } label: {
                Text(.gamesDrawAndGuessSaveNotNow)
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .disabled(viewModel.savePrompt == .saving)

            Button {
                Task { await viewModel.saveToMemories() }
            } label: {
                Text(.gamesDrawAndGuessSaveSave)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle(isLoading: viewModel.savePrompt == .saving))
            .frame(maxWidth: .infinity)
        }
    }
}

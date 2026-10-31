import SwiftUI

/// The drawer: the word, the canvas, the tools and Done. The partner's wrong
/// guesses show up in a line above the canvas while they watch.
struct DrawAndGuessDrawingView: View {
    @Bindable var viewModel: DrawAndGuessViewModel

    @State private var shownGuess: DrawAndGuessAttemptView?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var board: GameDrawingBoard { viewModel.board }

    /// The newest wrong guess, which the live row shows for a few seconds.
    private var newestWrongGuessID: UUID? {
        viewModel.round?.attempts.last { !$0.isCorrect }?.id
    }

    var body: some View {
        GamePhaseLayout(sharing: .publishes, sideMemory: viewModel.squareMemory) {
            VStack(spacing: PaeoniaSpacing.space8) {
                DrawAndGuessWordLine(word: DrawAndGuessAnswer.display(viewModel.round?.word ?? ""))
                liveRow
                GameLiveReactionButtons(isAvailable: viewModel.canSendLiveReaction, identifierPrefix: "draw") {
                    viewModel.sendLiveReaction($0)
                }
            }
        } square: { side in
            GameDrawingCanvas(
                board: board,
                side: side,
                onCanvasReady: viewModel.canvasReady,
                identifier: "draw.canvas"
            )
        } footer: {
            GameDrawingTools(board: board)
            GameDrawingDescriptionEditor(model: viewModel.drawingDescription, isGuessingGame: true,
                                         isLocked: board.isFinishing)
        } bottom: {
            Button {
                PaeoniaHaptics.drawingSent()
                GameSound.send.play()
                Task { await viewModel.finishDrawing() }
            } label: {
                Text(.commonDone)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(!viewModel.canFinishDrawing)
            .accessibilityLabel(Text(.gamesDrawAndGuessDrawDoneA11Y(viewModel.partnerName)))
            .accessibilityIdentifier("draw.done")
        }
        .modifier(WidgetDrawingPencilDoubleTap(viewModel: board))
        .gameClearDrawingToolbar(board: board, identifier: "draw.clear")
        .onChange(of: newestWrongGuessID) { _, id in
            guard id != nil, let attempt = viewModel.round?.attempts.last(where: { $0.id == id }) else { return }
            showGuess(attempt)
        }
        .onChange(of: viewModel.partnerPresence) { old, new in
            guard new != .away, new != old else { return }
            partnerPresenceChanged(from: old)
        }
        .task(id: shownGuess?.id) {
            guard shownGuess != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(PaeoniaMotion.meaningfulMoment) { shownGuess = nil }
        }
    }

    // MARK: Live row

    private var liveRow: some View {
        GameLiveRow {
            GamePresenceLabel(
                player: viewModel.partner,
                text: viewModel.partnerPresence.drawingLine(partnerName: viewModel.partnerName),
                isHere: viewModel.partnerPresence.isHere
            )
            .accessibilityIdentifier("draw.presence")
        } trailing: {
            if shownGuess != nil {
                guessCapsule
            }
        }
    }

    /// The latest guess wraps with the presence row when it needs more room.
    private var guessCapsule: some View {
        Text(.gamesDrawAndGuessDrawTried(viewModel.partnerName, (shownGuess?.text ?? " ").uppercased()))
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space4)
            .background(.paeoniaSurfacePrimary, in: Capsule(style: .continuous))
            .accessibilityHidden(true)
    }

    private func showGuess(_ attempt: DrawAndGuessAttemptView) {
        withAnimation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.cardReveal) {
            shownGuess = attempt
        }
        // The view model's attention cue plays the haptic, also when this view is not on screen.
        var announcement = AttributedString(
            String(localized: .gamesDrawAndGuessDrawTried(viewModel.partnerName, attempt.text.uppercased()))
        )
        announcement.accessibilitySpeechAnnouncementPriority = .low
        AccessibilityNotification.Announcement(announcement).post()
    }

    /// The partner came into the game, or their phone said what they are doing.
    private func partnerPresenceChanged(from old: DrawAndGuessPartnerPresence) {
        AccessibilityNotification.Announcement(
            String(localized: viewModel.partnerPresence.drawingLine(partnerName: viewModel.partnerName))
        ).post()
        guard !old.isHere else { return }
        PaeoniaHaptics.partnerDrawingReceived()
        GameSound.nudge.play(volume: 0.7)
    }
}

/// A centered word heading that stacks when space is tight.
struct DrawAndGuessWordLine: View {
    let word: String

    var body: some View {
        GameLiveRow {
            Text(.gamesDrawAndGuessDrawWordLabel)
                .paeoniaEyebrowStyle()
        } trailing: {
            Text(word)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityIdentifier("draw.word")
        }
        .accessibilityElement(children: .combine)
    }
}

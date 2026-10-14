import SwiftUI

/// The drawer: the word, the canvas, the tools and Done. The partner's wrong
/// guesses show up in a line above the canvas while they watch.
struct DrawAndGuessDrawingView: View {
    @Bindable var viewModel: DrawAndGuessViewModel

    @State private var shownGuess: DrawAndGuessAttemptView?
    @State private var partnerPulse: CGFloat = 1
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
        } bottom: {
            Button {
                PaeoniaHaptics.drawingSent()
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
            if viewModel.partnerPresence.isHere {
                GamePresenceLabel(
                    player: viewModel.partner,
                    text: viewModel.partnerPresence.drawingLine(partnerName: viewModel.partnerName),
                    showsRing: viewModel.partnerPresence == .watching,
                    scale: partnerPulse
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("draw.presence")
            } else {
                Text(.gamesDrawAndGuessDrawLater(viewModel.partnerName))
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityIdentifier("draw.presence")
            }
        } trailing: {
            guessCapsule
        }
    }

    /// The slot is always laid out, so nothing moves when a guess comes or goes.
    private var guessCapsule: some View {
        Text(.gamesDrawAndGuessDrawTried(viewModel.partnerName, (shownGuess?.text ?? " ").uppercased()))
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextSecondary)
            .lineLimit(1)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space4)
            .background(.paeoniaSurfacePrimary, in: Capsule(style: .continuous))
            .opacity(shownGuess == nil ? 0 : 1)
            .offset(y: shownGuess == nil || reduceMotion ? 0 : 0)
            .frame(height: 28)
            .accessibilityHidden(true)
    }

    private func showGuess(_ attempt: DrawAndGuessAttemptView) {
        withAnimation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.cardReveal) {
            shownGuess = attempt
        }
        if !board.isStrokeInProgress {
            PaeoniaHaptics.partnerDrawingReceived()
        }
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
        guard !reduceMotion else { return }
        withAnimation(PaeoniaMotion.stateChange) { partnerPulse = 1.12 }
        withAnimation(PaeoniaMotion.stateChange.delay(PaeoniaMotion.motionDefault)) { partnerPulse = 1 }
    }
}

/// "DRAW" and the word, on one line.
struct DrawAndGuessWordLine: View {
    let word: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8))
        layout {
            Text(.gamesDrawAndGuessDrawWordLabel)
                .font(PaeoniaTypography.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(.paeoniaTextTertiary)
            Text(word)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier("draw.word")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PaeoniaSpacing.space8)
        .accessibilityElement(children: .combine)
    }
}

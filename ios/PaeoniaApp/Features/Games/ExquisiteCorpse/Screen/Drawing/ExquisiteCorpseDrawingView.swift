import SwiftUI

/// The drawer: the part to draw, an optional idea, the strip of the part above
/// for a body or legs, the canvas, the tools and Done.
struct ExquisiteCorpseDrawingView: View {
    let viewModel: ExquisiteCorpseViewModel
    /// Matches the strip to the watched square on the way in. Nil with Reduce Motion.
    let handoff: Namespace.ID?

    /// Fixed when the screen opens. The screen fades out when the part is sent and
    /// the view model moves on to the partner's part, and must not change on the way.
    private let part: ExquisiteCorpsePartKind
    private let showsFirstHint: Bool

    @State private var partnerPulse: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var board: GameDrawingBoard { viewModel.board }

    init(viewModel: ExquisiteCorpseViewModel, handoff: Namespace.ID? = nil) {
        self.viewModel = viewModel
        self.handoff = handoff
        part = viewModel.part ?? .head
        showsFirstHint = viewModel.isFirstFigure
    }

    var body: some View {
        GamePhaseLayout(
            sharing: .publishes,
            sideMemory: viewModel.squareMemory,
            squareHeightRatio: part.hasStripAbove ? 1 + ExquisiteCorpseFold.stripFraction : 1
        ) {
            VStack(spacing: PaeoniaSpacing.space8) {
                ExquisiteCorpsePartLine(part: part)
                if showsFirstHint {
                    firstHint
                }
                ideaRow
                liveRow
            }
        } square: { side in
            ExquisiteCorpseDrawingSurface(
                board: board,
                side: side,
                part: part,
                partnerName: viewModel.partnerName,
                strip: viewModel.strip,
                stripLoadFailed: viewModel.stripLoadFailed,
                onRetryStrip: viewModel.retryLoadingStrip,
                handoff: handoff,
                onCanvasReady: viewModel.canvasReady
            )
            // Done owns the drawing while it queues it, so a stroke added now would be lost.
            .allowsHitTesting(!viewModel.isFinishing)
        } footer: {
            GameDrawingTools(board: board)
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
            .accessibilityLabel(Text(.exquisiteCorpseDrawDoneA11Y(viewModel.partnerName)))
            .accessibilityIdentifier("corpse.done")
        }
        .modifier(WidgetDrawingPencilDoubleTap(viewModel: board))
        .gameClearDrawingToolbar(board: board, identifier: "corpse.clear")
        .onChange(of: viewModel.partnerPresence) { old, new in
            guard new != .away, new != old else { return }
            partnerPresenceChanged(from: old)
        }
    }

    // MARK: Rows

    /// The only teaching in the game, on the first head.
    private var firstHint: some View {
        Text(.exquisiteCorpseDrawFirstHint(viewModel.partnerName))
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaeoniaSpacing.space8)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("corpse.firstHint")
    }

    /// Always laid out at the same height, so nothing below it moves when the chip
    /// comes and goes. Without a dealt deck there is nothing to ask for.
    @ViewBuilder
    private var ideaRow: some View {
        if viewModel.hasIdeas || viewModel.idea != nil {
            ExquisiteCorpseIdeaRow(
                idea: viewModel.idea?.text,
                onAsk: viewModel.askIdea,
                onShuffle: viewModel.shuffleIdea,
                onRemove: viewModel.removeIdea
            )
        } else {
            Color.clear.frame(height: PaeoniaSpacing.compactButtonHeight)
        }
    }

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
                .accessibilityIdentifier("corpse.presence")
            } else {
                Text(.exquisiteCorpseDrawLater(viewModel.partnerName))
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityIdentifier("corpse.presence")
            }
        } trailing: {
            EmptyView()
        }
    }

    /// The partner came into the game, or their phone said what they are doing.
    private func partnerPresenceChanged(from old: ExquisiteCorpsePartnerPresence) {
        AccessibilityNotification.Announcement(
            String(localized: viewModel.partnerPresence.drawingLine(partnerName: viewModel.partnerName))
        ).post()
        guard !old.isHere else { return }
        if !board.isStrokeInProgress {
            PaeoniaHaptics.partnerDrawingReceived()
        }
        GameSound.nudge.play(volume: 0.7)
        guard !reduceMotion else { return }
        withAnimation(PaeoniaMotion.stateChange) { partnerPulse = 1.12 }
        withAnimation(PaeoniaMotion.stateChange.delay(PaeoniaMotion.motionDefault)) { partnerPulse = 1 }
    }
}

/// "YOUR PART" and "Draw the head", on one line.
struct ExquisiteCorpsePartLine: View {
    let part: ExquisiteCorpsePartKind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8))
        layout {
            Text(.exquisiteCorpseDrawEyebrow)
                .font(PaeoniaTypography.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.4)
                .foregroundStyle(.paeoniaTextTertiary)
            Text(title)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier("corpse.partTitle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PaeoniaSpacing.space8)
        .accessibilityElement(children: .combine)
    }

    private var title: LocalizedStringResource {
        switch part {
        case .head: .exquisiteCorpseDrawHead
        case .body: .exquisiteCorpseDrawBody
        case .legs: .exquisiteCorpseDrawLegs
        }
    }
}

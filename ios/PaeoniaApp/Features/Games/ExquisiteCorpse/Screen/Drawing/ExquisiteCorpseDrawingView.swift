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

    @State private var isCompositionPresented = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                if showsFirstHint {
                    firstHint
                }
                liveRow
                ideaRow
                if dynamicTypeSize.isAccessibilitySize {
                    nativeCreation
                }
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
            if part.showsFoldLine {
                Text(.exquisiteCorpseDrawFoldLabel(viewModel.partnerName))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GameDrawingTools(board: board, showsComposition: !dynamicTypeSize.isAccessibilitySize) {
                isCompositionPresented = true
            }
            if !dynamicTypeSize.isAccessibilitySize {
                GameDrawingDescriptionEditor(model: viewModel.drawingDescription, isLocked: viewModel.isFinishing)
            }
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
        .drawingCompositionSheet(
            isPresented: $isCompositionPresented,
            drawing: board.drawing, side: board.canvasSide, isLocked: viewModel.isFinishing
        ) { board.applyEdit($0) }
        .modifier(WidgetDrawingPencilDoubleTap(viewModel: board))
        .gameClearDrawingToolbar(board: board, identifier: "corpse.clear")
        .onChange(of: viewModel.partnerPresence) { old, new in
            guard new != .away, new != old else { return }
            partnerPresenceChanged(from: old)
        }
    }

    // Native creation stays before the gesture canvas when enlarged content must scroll.
    private var nativeCreation: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            DrawingCompositionButton { isCompositionPresented = true }
                .disabled(viewModel.isFinishing)
            GameDrawingDescriptionEditor(model: viewModel.drawingDescription, isLocked: viewModel.isFinishing)
        }
    }

    // MARK: Rows

    /// The only teaching in the game, on the first head.
    private var firstHint: some View {
        Text(.exquisiteCorpseDrawFirstHint(viewModel.partnerName))
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.horizontal, PaeoniaSpacing.space8)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("corpse.firstHint")
    }

    private var ideaRow: some View {
        ExquisiteCorpseIdeaRow(
            idea: viewModel.idea?.text,
            canAsk: viewModel.hasIdeas,
            onAsk: viewModel.askIdea,
            onShuffle: viewModel.shuffleIdea,
            onRemove: viewModel.removeIdea
        )
    }

    private var liveRow: some View {
        GameLiveRow {
            GamePresenceLabel(
                player: viewModel.partner,
                text: viewModel.partnerPresence.drawingLine(partnerName: viewModel.partnerName),
                isHere: viewModel.partnerPresence.isHere
            )
            .accessibilityIdentifier("corpse.presence")
        } trailing: {
            EmptyView()
        }
    }

    /// The partner came into the game, or their phone said what they are doing.
    private func partnerPresenceChanged(from old: ExquisiteCorpsePartnerPresence) {
        guard !old.isHere else { return }
        if !board.isStrokeInProgress {
            PaeoniaHaptics.partnerDrawingReceived()
        }
        GameSound.nudge.play()
    }
}

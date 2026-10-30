import SwiftUI

/// The partner draws now, and this person watches. The partner's square sits
/// under the back of the folded paper. A soft glow moves behind the paper where
/// their pen is, and the strip at the bottom shows the strokes that reach it. When
/// the partner taps Done, the paper gives one soft pulse and the line says so,
/// until the server moves the turn and the strip slides into this person's canvas.
struct ExquisiteCorpseWatchView: View {
    let viewModel: ExquisiteCorpseViewModel
    /// Matches the strip of this square to the next canvas. Nil with Reduce Motion.
    let handoff: Namespace.ID?

    /// Fixed when the screen opens. The screen fades out when the turn comes
    /// around, and must not change its words on the way.
    private let watchedPart: ExquisiteCorpsePartKind

    init(viewModel: ExquisiteCorpseViewModel, handoff: Namespace.ID?) {
        self.viewModel = viewModel
        self.handoff = handoff
        watchedPart = viewModel.part ?? .head
    }

    var body: some View {
        // The next canvas has a strip above it, so the square takes the side that
        // canvas will have, and the strip can slide into place without resizing.
        GamePhaseLayout(
            sharing: .inherits,
            sideMemory: viewModel.squareMemory,
            squareHeightRatio: watchedPart.next == nil ? 1 : 1 + ExquisiteCorpseFold.stripFraction
        ) {
            liveRow
        } square: { side in
            GameSquare(side: side) {
                ExquisiteCorpseFoldedPaper(
                    side: side,
                    penPosition: viewModel.partnerPen,
                    strip: viewModel.partnerStrip,
                    pulse: viewModel.partnerDonePulse,
                    showsStrip: watchedPart.hasStrip,
                    accessibilityLabel: title
                )
            }
            .overlay(alignment: .bottom) {
                handoffMarker(side: side)
            }
        } footer: {
            hint
        } bottom: {
            EmptyView()
        }
        .exquisiteCorpseInviteToolbar(viewModel)
        .onChange(of: viewModel.partnerDonePulse) { _, _ in
            // The view model's attention cue taps once the part reaches the server.
            AccessibilityNotification.Announcement(String(localized: title)).post()
        }
    }

    // MARK: Rows

    private var liveRow: some View {
        GameLiveRow {
            GamePresenceLabel(
                player: viewModel.partner,
                text: title,
                isHere: viewModel.partnerPresence.isHere
            )
                .accessibilityIdentifier("corpse.watching")
        } trailing: {
            EmptyView()
        }
    }

    /// "Robin is drawing the head", and "Robin finished the head" after Done. The
    /// legs have no line of their own for Done, because the reveal opens next.
    private var title: LocalizedStringResource {
        let name = viewModel.partnerName
        if viewModel.partnerFinishedPart != nil {
            switch watchedPart {
            case .head: return .exquisiteCorpseWaitFinishedHead(name)
            case .body: return .exquisiteCorpseWaitFinishedBody(name)
            case .legs: return .exquisiteCorpseWaitOpening
            }
        }
        switch watchedPart {
        case .head: return .exquisiteCorpseWaitDrawingNowHead(name)
        case .body: return .exquisiteCorpseWaitDrawingNowBody(name)
        case .legs: return .exquisiteCorpseWaitDrawingNowLegs(name)
        }
    }

    /// Nothing follows the legs, so there are no lines to connect to, and the
    /// whole creature opens next.
    private var hint: some View {
        Text(watchedPart.next == nil ? .exquisiteCorpseWaitHintLiveLegs : .exquisiteCorpseWaitHintLive)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PaeoniaSpacing.space8)
            .accessibilityIdentifier("corpse.watch.hint")
    }

    /// An invisible frame over the strip of the square. The strip of the next
    /// canvas takes its place from here, so it slides from the bottom of this
    /// square to the top of that canvas.
    @ViewBuilder
    private func handoffMarker(side: CGFloat) -> some View {
        if let handoff, watchedPart.next != nil {
            Color.clear
                .frame(width: side, height: side * ExquisiteCorpseFold.stripFraction)
                .matchedGeometryEffect(id: ExquisiteCorpseHandoff.strip, in: handoff)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

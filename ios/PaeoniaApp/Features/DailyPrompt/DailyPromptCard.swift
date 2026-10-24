import SwiftUI

extension EnvironmentValues {
    /// True while the daily answer flow covers the tabs. The Home card reads it to wait for
    /// the flow to close before it plays the seal moment.
    @Entry var dailyFlowIsPresented = false
}

/// Today's Daily Challenge on the Home tab and the Questions tab.
///
/// While there is something to do (and while the questions load) it is the picture card
/// with the sealed envelope (`DailyPromptHeroCard`). Once today's question is answered it is
/// a short row (`DailyPromptCompactCard`). The envelope holds the partner's answers, so it
/// opens only once they can be read. When the last answer comes in and the partner has
/// answered, the seal breaks, the envelope opens and the card shrinks. Otherwise the card
/// shrinks with the envelope still sealed, and it opens on the short row when the partner
/// answers (see `playMoment` and `playOpening`). If the card is out of sight then,
/// such as when the flow closes onto the Questions tab, the moment plays when it is next
/// seen.
///
/// The card is the source the answering flow zooms out of; its parent marks it with
/// `.matchedTransitionSource`, so the card itself appears to grow into the full-screen
/// flow when tapped.
struct DailyPromptCard: View {
    let state: DailyChallengeCardState
    /// The partner's display name, used by the "See %@'s answers" CTA so it names the
    /// partner instead of saying "partner".
    var partnerName: String
    /// The partner's profile photo, shown on the locked partner-question rows.
    var partnerPhotoAssetID: UUID?
    var prefersPartnerAnswersWhenComplete = false
    /// Set on Home so a tapped locked row is the source its answer flow zooms out of.
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void = {}
    /// Opens the answer flow of an earlier question shown as a locked row.
    var onOpenPartnerQuestion: (UUID) -> Void = { _ in }

    private enum MomentPhase {
        case idle
        /// The card is complete but still looks active. It waits until it is in sight
        /// with the flow closed.
        case waiting
        /// The picture card's moment is playing.
        case breaking
        /// The short row's envelope is opening.
        case opening
    }

    /// How long the seal moment takes after the answer flow closes, from the wait for the
    /// zoom back to the card settling. The notification ask waits this long, so it doesn't
    /// slide up over the moment.
    static let momentLength = Duration.milliseconds(2_250)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dailyFlowIsPresented) private var flowIsPresented
    @State private var hold = DailyPromptCardHold()
    @State private var phase = MomentPhase.idle
    @State private var sealBreak = 0.0
    @State private var sealBreaks = 0
    @State private var envelopeOpening = DailyPromptEnvelopeOpening.closed
    /// The short row's envelope while it opens. Nil shows what the state says.
    @State private var compactOpening: DailyPromptEnvelopeOpening?
    @State private var compactSealBreak = 0.0
    /// The partner's answers became readable while the short row was up. The envelope
    /// opens when the card is next seen.
    @State private var opensWhenSeen = false
    /// Whether the last state that was not loading could read the partner's answers.
    /// Nil until one arrives, so a launch into readable answers shows them open at once.
    @State private var wasReadable: Bool?
    @State private var isOnScreen = false
    @State private var momentTask: Task<Void, Never>?

    var body: some View {
        // While the moment is pending the card draws its last active state.
        let shown = hold.shownState(for: state)
        let art = DailyPromptCardArt(shown)
        let copy = DailyPromptCardCopy(
            state: shown,
            partnerName: partnerName,
            prefersPartnerAnswersWhenComplete: prefersPartnerAnswersWhenComplete
        )
        Group {
            switch art.shape {
            case .hero:
                DailyPromptHeroCard(
                    state: shown,
                    art: art,
                    copy: copy,
                    partnerPhotoAssetID: partnerPhotoAssetID,
                    sealBreak: sealBreak,
                    envelopeOpening: envelopeOpening,
                    zoomNamespace: zoomNamespace,
                    onAnswer: onAnswer,
                    onOpenPartnerQuestion: onOpenPartnerQuestion
                )
                .transition(.opacity)
            case .compact:
                DailyPromptCompactCard(
                    state: shown,
                    copy: copy,
                    partnerPhotoAssetID: partnerPhotoAssetID,
                    seal: art.seal,
                    opening: compactOpening ?? (art.isEnvelopeOpen ? .letterOut : .closed),
                    sealBreak: compactSealBreak,
                    zoomNamespace: zoomNamespace,
                    onAnswer: onAnswer,
                    onOpenPartnerQuestion: onOpenPartnerQuestion
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
            }
        }
        .onChange(of: state, initial: true) { _, new in observe(new) }
        .onChange(of: flowIsPresented) { scheduleMomentIfSeen() }
        .onChange(of: scenePhase) { scheduleMomentIfSeen() }
        .onAppear {
            isOnScreen = true
            scheduleMomentIfSeen()
        }
        .onDisappear {
            isOnScreen = false
            // A moment that already started finishes at once. One still waiting keeps
            // waiting for the card to come back.
            switch phase {
            case .breaking:
                endMoment()
            case .opening:
                endOpening()
            case .idle, .waiting:
                momentTask?.cancel()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: sealBreaks)
    }

    // MARK: Seal moment

    private func observe(_ new: DailyChallengeCardState) {
        hold.observe(new)
        if case .active = new.kind {
            envelopeOpening = .closed
            if phase == .opening {
                endOpening()
            }
            opensWhenSeen = false
            compactOpening = nil
        }
        noteReadability(new)
        if hold.isHolding(for: new) {
            if phase == .idle {
                beginMoment()
            }
        } else if phase == .waiting || phase == .breaking {
            // The day changed before the moment played. Ending it clears the hold, so
            // the new day's state is noted again.
            endMoment()
            hold.observe(new)
        }
    }

    /// The partner answered after this person's part was done, so the short row's sealed
    /// envelope opens once the card is seen. The picture card's moment opens it by itself.
    private func noteReadability(_ new: DailyChallengeCardState) {
        guard new.kind != .loading else { return }
        let isReadable = DailyPromptCardArt.partnerAnswersAreReadable(new)
        if wasReadable == false, isReadable, !hold.isHolding(for: new) {
            opensWhenSeen = true
            compactOpening = .closed
            scheduleMomentIfSeen()
        }
        wasReadable = isReadable
    }

    /// The last answer came in. The answer flow is usually still open, and it often closes
    /// onto the Questions tab, so the card keeps its sealed look until the person sees it.
    private func beginMoment() {
        phase = .waiting
        scheduleMomentIfSeen()
    }

    /// Starts a waiting moment once the card is in sight with the flow closed and the app
    /// in front. Otherwise it holds off, and a later appear, flow close or return to the
    /// app tries again.
    private func scheduleMomentIfSeen() {
        guard phase == .waiting || (phase == .idle && opensWhenSeen) else { return }
        guard isOnScreen, !flowIsPresented, scenePhase == .active else {
            momentTask?.cancel()
            return
        }
        scheduleMoment()
    }

    /// Waits for the flow's zoom back or the tab switch to land on the card, so the person
    /// sees the seal break.
    private func scheduleMoment() {
        momentTask?.cancel()
        momentTask = Task {
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            if phase == .waiting {
                await playMoment()
            } else {
                await playOpening()
            }
        }
    }

    /// This person's part is done. With the partner's answers readable, the seal breaks
    /// with a crack and a tap, the flap folds back and the letter rises. Then the card
    /// shrinks to the short row, sealed if the partner has not answered yet. With Reduce
    /// Motion nothing moves: the seal is gone at once and the card crossfades. The sound
    /// goes quiet with the silent switch. The tap stays.
    private func playMoment() async {
        phase = .breaking
        sealBreaks += 1
        GameSound.fold.play(volume: 0.8)
        if !DailyPromptCardArt.partnerAnswersAreReadable(state) {
            try? await Task.sleep(for: .milliseconds(150))
        } else if reduceMotion {
            sealBreak = 1
            try? await Task.sleep(for: .milliseconds(150))
        } else {
            withAnimation(.easeOut(duration: 0.4)) { sealBreak = 1 }
            guard await openEnvelope() else { return }
        }
        guard !Task.isCancelled else { return }
        let collapse = reduceMotion
            ? PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast)
            : PaeoniaMotion.heroMorph
        withAnimation(collapse) { endMoment() }
    }

    /// Folds the flap back once the seal is off, then lifts the letter so it shows for a
    /// beat before the card shrinks. Returns false if the moment was cancelled.
    private func openEnvelope() async -> Bool {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return false }
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) { envelopeOpening = .flapOpening }
        // The flap is past upright, so it can go behind the letter.
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return false }
        GameSound.flip.play(volume: 0.6)
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) { envelopeOpening = .letterOut }
        try? await Task.sleep(for: .milliseconds(600))
        return !Task.isCancelled
    }

    /// The partner's answers came in after the card shrank. The short row's seal breaks,
    /// its flap folds back and the letter rises.
    private func playOpening() async {
        phase = .opening
        opensWhenSeen = false
        sealBreaks += 1
        GameSound.fold.play(volume: 0.8)
        guard !reduceMotion else {
            endOpening()
            return
        }
        withAnimation(.easeOut(duration: 0.4)) { compactSealBreak = 1 }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) { compactOpening = .flapOpening }
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        GameSound.flip.play(volume: 0.6)
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) { compactOpening = .letterOut }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        endOpening()
    }

    /// Hands the short row's envelope back to the state, which has it open.
    private func endOpening() {
        momentTask?.cancel()
        momentTask = nil
        phase = .idle
        opensWhenSeen = false
        compactOpening = nil
        compactSealBreak = 0
    }

    /// Shows the card's real state.
    private func endMoment() {
        momentTask?.cancel()
        momentTask = nil
        hold.release()
        phase = .idle
        sealBreak = 0
    }
}

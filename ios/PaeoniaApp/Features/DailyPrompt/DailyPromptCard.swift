import SwiftUI

extension EnvironmentValues {
    /// True while the daily answer flow covers the tabs. The Home card reads it to wait for
    /// the flow to close before it plays the seal moment.
    @Entry var dailyFlowIsPresented = false
}

/// Today's Daily Challenge on the Home tab and the Questions tab.
///
/// While there is something to do (and while the questions load) it is the picture card
/// with the sealed envelope (`DailyPromptHeroCard`). Once today's questions are done it is
/// a short row (`DailyPromptCompactCard`). When the last answer comes in, the seal breaks
/// first and then the card shrinks (see `playMoment`). If the card is out of sight then,
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
    /// Opens the answer flow of a partner question shown as a locked row.
    var onOpenPartnerQuestion: (UUID) -> Void = { _ in }

    private enum MomentPhase {
        case idle
        /// The card is complete but still looks active. It waits until it is in sight
        /// with the flow closed.
        case waiting
        /// The seal is breaking.
        case breaking
    }

    /// How long the seal moment takes after the answer flow closes, from the wait for the
    /// zoom back to the card settling. The notification ask waits this long, so it doesn't
    /// slide up over the moment.
    static let momentLength = Duration.milliseconds(1_600)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dailyFlowIsPresented) private var flowIsPresented
    @State private var hold = DailyPromptCardHold()
    @State private var phase = MomentPhase.idle
    @State private var sealBreak = 0.0
    @State private var sealBreaks = 0
    @State private var envelopePopsOpen = false
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
                    envelopePopsOpen: envelopePopsOpen,
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
            if phase == .breaking {
                endMoment()
            } else {
                momentTask?.cancel()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: sealBreaks)
    }

    // MARK: Seal moment

    private func observe(_ new: DailyChallengeCardState) {
        hold.observe(new)
        if case .active = new.kind {
            envelopePopsOpen = false
        }
        if hold.isHolding(for: new) {
            if phase == .idle {
                beginMoment()
            }
        } else if phase != .idle {
            // The day changed before the moment played. Ending it clears the hold, so
            // the new day's state is noted again.
            endMoment()
            hold.observe(new)
        }
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
        guard phase == .waiting else { return }
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
            await playMoment()
        }
    }

    /// The seal breaks with a crack and a tap, then the card shrinks to the short row and
    /// its envelope pops open. With Reduce Motion nothing moves: the seal is gone at once
    /// and the card crossfades. The sound goes quiet with the silent switch. The tap stays.
    private func playMoment() async {
        phase = .breaking
        sealBreaks += 1
        GameSound.fold.play(volume: 0.8)
        if reduceMotion {
            sealBreak = 1
        } else {
            withAnimation(.easeOut(duration: 0.4)) { sealBreak = 1 }
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 420))
        guard !Task.isCancelled else { return }
        envelopePopsOpen = !reduceMotion
        let collapse = reduceMotion
            ? PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast)
            : PaeoniaMotion.heroMorph
        withAnimation(collapse) { endMoment() }
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

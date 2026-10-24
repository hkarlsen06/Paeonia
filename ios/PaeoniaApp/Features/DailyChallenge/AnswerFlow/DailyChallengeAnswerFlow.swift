import Foundation
import SwiftUI

/// The focused, full-screen flow for answering one daily question.
///
/// It is presented as a full-screen cover that zooms out of the card that opened it: the
/// Home or Questions card for today's question, or a question's own row. It shows the
/// question and its composer, and a quiet "Skip" swaps today's question for a fresh one
/// while neither partner has answered it. Sending turns the screen over to what comes
/// next. When the partner had answered already, their answer is revealed in place with a
/// chime and a petal burst, and the screen offers Done and Open chat. Otherwise the
/// streak celebration shows. The Close button, or a drag down, shrinks it back.
struct DailyChallengeAnswerFlow: View {
    let viewModel: DailyChallengeViewModel
    /// The question to answer. Nil answers today's question.
    var questionID: UUID?
    var onClose: () -> Void = {}
    /// Builds the streak-restore purchase view model the completion screen uses to
    /// buy a slipped streak back in place. Called once, lazily, the first time a
    /// completion with a restorable streak appears.
    var makeStreakRestoreViewModel: @MainActor () -> StreakRestoreViewModel = {
        StreakRestoreViewModel(streak: .none, userID: nil)
    }
    /// Claims the streak milestone the finished day reaches, if this phone has not
    /// celebrated it yet. See `StreakMilestoneStore.claim`.
    var claimStreakMilestone: @MainActor (Int) -> Int? = { _ in nil }
    /// Closes the flow and opens a question's chat: the reveal's Open chat, and the note
    /// about an earlier answer.
    var onOpenQuestionChat: (DailyChallengeQuestion) -> Void = { _ in }

    @Environment(PaeoniaBannerCenter.self) var bannerCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var didCelebrate = false
    @State var celebratedMilestone: Int?
    /// The in-place streak-restore purchase driver, created only when a slipped
    /// streak's completion appears. Drives the completion screen's buy button and the
    /// revive-and-refill celebration once a purchase lands.
    @State var restoreViewModel: StreakRestoreViewModel?
    @State var committedAnswerHold: DailyAnswerStepVisualHold?
    /// The question whose partner answer the reveal shows. It is captured on send, so
    /// the reveal stays on screen while the live question list changes under it.
    @State var revealQuestion: DailyChallengeQuestion?
    @State var isAwaitingReveal = false
    /// The question the user sent an answer to in this flow. When the partner's answer
    /// turns out to be in once the exchange is confirmed, the screen turns to the reveal,
    /// even if the phone did not know about it when the user sent.
    @State var sentQuestionID: UUID?
    /// The question the user just answered that they had answered on an earlier day. The
    /// note offers their old answers, and goes away on its own. It waits for the chat to be
    /// available, which can come a moment after the send, when the partner's answer opens.
    @State var earlierCandidate: DailyChallengeQuestion?
    @FocusState var isComposerFocused: Bool

    enum Phase {
        case loading
        case answering
        case unavailable
        case complete
    }

    /// The question on screen, from the live snapshot: the one this flow opened for, or
    /// today's question. A skip swaps today's question, and the flow follows it.
    var currentQuestion: DailyChallengeQuestion? {
        if let questionID {
            return viewModel.knownQuestion(questionID)
        }
        return viewModel.snapshot.todayQuestion
    }

    var phase: Phase {
        if didCelebrate { return .complete }
        if currentQuestion != nil { return .answering }
        if viewModel.isStarting || viewModel.isLoading { return .loading }
        return .unavailable
    }

    /// The streak shown on the completion celebration.
    ///
    /// Answers send local-first, so the stored streak may not yet reflect today
    /// when this screen appears. We predict today's increment from the stored
    /// streak and the couple's local date — the same rule the server applies once
    /// the answer lands — so the number is right immediately and offline.
    var currentStreak: Int {
        StreakCelebration.celebratedCount(
            serverCurrentCount: viewModel.streak.currentCount,
            lastQualifiedDate: viewModel.streak.lastQualifiedDate,
            todayLocalDate: viewModel.snapshot.currentDayLocalDate,
            partnerContributedToday: viewModel.streak.partnerContributedToday
        )
    }

    /// Drives the answering → completion swap. A gentle celebratory bloom under
    /// motion; a plain timed cross-fade when Reduce Motion is on.
    var celebrateAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: PaeoniaMotion.motionDefault)
            : PaeoniaMotion.celebrationReveal
    }

    /// The completion surface grows in from slightly smaller as the question fades
    /// out, so the streak screen reads as a reward arriving rather than a swap.
    /// Reduce Motion drops the scale and keeps only the cross-fade.
    var completionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.92))
    }

    var body: some View {
        ZStack {
            if let revealQuestion {
                revealContent(revealQuestion)
            } else {
                phaseContent
            }
        }
        .paeoniaReadableWidth()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Let the plum bleed under the keyboard's safe-area region too. Keyboard
        // avoidance otherwise shrinks this surface above the keyboard, so the window's
        // black showed through the keyboard's rounded top corners.
        .background { PaeoniaGlowBackground() }
        .animation(celebrateAnimation, value: didCelebrate)
        .overlay(alignment: .top) {
            if let earlierAnswer, !showsEarlierAnswerInline {
                earlierAnswerNote(earlierAnswer)
                    .padding(.top, PaeoniaSpacing.screenTopSpacing)
                    .transition(.opacity)
            }
        }
        .task(id: earlierCandidate?.id) {
            guard earlierCandidate != nil else { return }
            try? await Task.sleep(for: Self.earlierAnswerNoteDuration)
            guard !Task.isCancelled else { return }
            withAnimation(PaeoniaMotion.stateChange) { earlierCandidate = nil }
        }
        .onChange(of: sentQuestionIsRevealed) { _, revealed in
            guard revealed, revealQuestion == nil, let sentQuestionID,
                  let live = viewModel.knownQuestion(sentQuestionID)
            else { return }
            withAnimation(PaeoniaMotion.meaningfulMoment) { revealQuestion = live }
        }
        .onChange(of: wasAnswerReturned) { _, returned in
            guard returned else { return }
            withAnimation(PaeoniaMotion.stateChange) { revealQuestion = nil }
        }
        .onChange(of: viewModel.notice) { _, notice in showBanner(for: notice) }
    }
}

#if DEBUG
#Preview {
    DailyChallengeAnswerFlowPreviewHost()
}

private struct DailyChallengeAnswerFlowPreviewHost: View {
    @State var viewModel = DailyChallengeViewModel(service: PreviewDailyChallengeService())

    var body: some View {
        DailyChallengeAnswerFlow(viewModel: viewModel)
            .environment(PaeoniaBannerCenter())
            .preferredColorScheme(.dark)
            .task {
                await viewModel.configure(currentUserID: PreviewDailyChallengeService.userID)
            }
    }
}
#endif

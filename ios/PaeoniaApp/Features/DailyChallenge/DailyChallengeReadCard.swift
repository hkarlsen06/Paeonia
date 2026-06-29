import SwiftUI

/// A "saved, sending" answer to keep visible in a read overview while it finishes
/// sending: a photo/voice note plays from its staged bytes, a partner pick and/or text
/// caption show what was chosen or written. Any combination can be present.
struct DailySendingPreview {
    var mediaKind: DailyChallengeAnswerKind = .photo
    var mediaData: Data?
    var voiceDurationMs: Int?
    var partnerChoiceName: String?
    var text: String?
}

/// A read-only card showing a question and whatever is visible about it: the two
/// people's status, and any revealed answers. It is the shared building block for
/// every place a question is *shown* rather than answered — the Questions tab's
/// read sections and the Questions history flow.
///
/// The answer affordance is optional and off by default, so a card is purely
/// read-only unless a caller opts in. The Questions tab opts in for a partner
/// question the user can still answer (showing the CTA and acting as the zoom
/// source for the answer flow); the history flow never does, so a historical card
/// only ever reads back the exchange.
struct DailyChallengeReadCard: View {
    let question: DailyChallengeQuestion
    var participants = DailyChallengeParticipants()
    var sending: DailySendingPreview?
    var isOwnChallengeComplete = true
    var zoomNamespace: Namespace.ID?
    var onAnswer: () -> Void = {}

    /// A partner question the user can still answer to reveal the reply. When sending,
    /// the card shows the "saved, sending" preview instead, so this stays false.
    private var isAnswerable: Bool {
        sending == nil && question.origin == .partner && question.isAvailableToAnswer
    }

    /// Whether tapping the CTA can actually open the answer flow. Answering a
    /// partner's question is gated behind finishing your own three first, so until
    /// then the CTA is shown but locked (and doesn't morph into the flow).
    private var canOpenAnswerFlow: Bool {
        isAnswerable && isOwnChallengeComplete
    }

    var body: some View {
        PaeoniaCard {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                Text(question.prompt)
                    .font(PaeoniaTypography.title)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let sending {
                    // Still saving: shows whatever was saved (photo, pick, and/or
                    // caption), so the usual "not answered" status would only contradict it.
                    DailySendingAnswerView(
                        mediaKind: sending.mediaKind,
                        mediaData: sending.mediaData,
                        voiceDurationMs: sending.voiceDurationMs,
                        partnerChoiceName: sending.partnerChoiceName,
                        text: sending.text
                    )
                } else {
                    DailyQuestionStatusView(question: question)

                    if isAnswerable {
                        // The CTA itself carries the call to action (answer to reveal,
                        // or finish your own first), so no extra explanatory line.
                        answerButton
                    } else {
                        DailyAnswerDetailsView(question: question, participants: participants)
                    }
                }
            }
        }
        // Answerable cards are the source the single-question flow zooms out of, so the
        // tapped card appears to grow into the full-screen flow. Only cards that can
        // open the flow carry it.
        .zoomSource(question.id, in: canOpenAnswerFlow ? zoomNamespace : nil)
    }

    /// The same primary CTA the daily prompt card uses. When the user still has their
    /// own questions to finish it stays visible but disabled, so it reads as a clear
    /// "do yours first" rather than disappearing.
    private var answerButton: some View {
        Button(action: onAnswer) {
            Text(canOpenAnswerFlow ? .dailyChallengePartnerAnswerCta : .dailyChallengePartnerLockedCta)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!canOpenAnswerFlow)
    }
}

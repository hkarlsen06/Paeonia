import SwiftUI

/// The user's answer on the waiting page while it is still sending, drawn like the
/// answer bubble it turns into once this phone has it.
struct DailyChatSendingAnswerRow: View {
    let answer: DailySendingPreview

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            Label {
                Text(.dailyChallengeYourAnswerTitle)
            } icon: {
                Image(systemName: "quote.opening")
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(Color.paeoniaTextPrimary.opacity(0.72))

            DailySendingAnswerView(
                mediaKind: answer.mediaKind,
                mediaData: answer.mediaData,
                voiceDurationMs: answer.voiceDurationMs,
                partnerChoiceName: answer.partnerChoiceName,
                text: answer.text,
                showsSendingStatus: answer.isHeldOnPhone
            )
        }
        .padding(.horizontal, PaeoniaSpacing.space12 + 2)
        .padding(.vertical, PaeoniaSpacing.space8 + 2)
        .background(.paeoniaAccentSecondary, in: ThreadChatBubbleShape.shape(for: .standalone(isCurrentUser: true)))
        .frame(maxWidth: 360, alignment: .trailing)
        .padding(.horizontal, PaeoniaSpacing.space12)
        .padding(.vertical, PaeoniaSpacing.space4)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .contain)
    }
}

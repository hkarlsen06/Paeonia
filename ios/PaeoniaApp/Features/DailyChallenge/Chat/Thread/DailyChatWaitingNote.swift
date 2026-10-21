import SwiftUI

/// A short centered note under a day's answers that says what the day is waiting for.
struct DailyChatWaitingNote: View {
    let waiting: DailyChatRound.Waiting
    let partnerName: String

    var body: some View {
        Text(text)
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.vertical, PaeoniaSpacing.space12)
    }

    private var text: LocalizedStringResource {
        switch waiting {
        case .partnerBeforeChat: .dailyChatWaitingPartner(partnerName)
        case .partner: .dailyChatRoundWaitingPartner(partnerName)
        case .yourAnswer: .dailyChatRoundWaitingYou(partnerName)
        case .reveal: .dailyChallengePartnerRevealWaiting(partnerName)
        }
    }
}

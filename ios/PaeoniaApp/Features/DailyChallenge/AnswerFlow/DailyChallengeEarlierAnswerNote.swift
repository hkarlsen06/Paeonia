import SwiftUI

/// What the answer flow remembers about a question the user answered on an earlier
/// day, so a small note can offer the old answers right after they answer it again.
nonisolated struct DailyChallengeEarlierAnswer: Equatable, Sendable {
    /// The day the user just answered. The note opens the question's chat on it.
    let question: DailyChallengeQuestion
    /// The couple-local date (`yyyy-MM-dd`) of the user's latest earlier answer.
    let localDate: String

    /// Nil when the user has not answered the question before, or when its chat can't
    /// open yet because the partner never answered it. The note leads to that chat.
    init?(question: DailyChallengeQuestion) {
        guard question.earlierRoundCount > 0, question.isChatAvailable,
              let localDate = question.latestEarlierRoundLocalDate
        else { return nil }
        self.question = question
        self.localDate = localDate
    }

    var id: UUID { question.id }

    /// The earlier date as a short, readable day. The year shows only when it is not this year.
    func dateText(now: Date = .now) -> String {
        guard let date = DailyChallengeHistory.parseLocalDate(localDate) else { return localDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var style = Date.FormatStyle(timeZone: calendar.timeZone).day().month(.wide)
        if calendar.component(.year, from: date) != Calendar.current.component(.year, from: now) {
            style = style.year()
        }
        return date.formatted(style)
    }
}

/// A small note under the answer flow's progress bar: the user answered this question
/// before, and one tap shows both answers then and now in the question's chat. It is
/// quiet on purpose and never stops the user from moving on to the next question.
struct DailyChallengeEarlierAnswerNote: View {
    let earlierAnswer: DailyChallengeEarlierAnswer
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var openButton: some View {
        Button(action: onOpen) {
            HStack(spacing: PaeoniaSpacing.space12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                    Text(.dailyChallengeEarlierAnswerTitle)
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                    Text(.dailyChallengeEarlierAnswerDate(earlierAnswer.dateText()))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(.dailyChallengeEarlierAnswerHint))
    }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            openButton

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.dailyChallengeEarlierAnswerDismiss))
        }
        .padding(.leading, PaeoniaSpacing.space16)
        .padding(.trailing, PaeoniaSpacing.space8)
        .padding(.vertical, PaeoniaSpacing.space8)
        .background(
            .paeoniaSurfaceSecondary,
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous)
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    }
}

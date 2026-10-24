import SwiftUI

extension DailyFlowZoom {
    /// The zoom source of a locked row on the Home card. It differs from the question
    /// id, which the Questions tab list uses, so the two tabs never share a source.
    static func homePartnerQuestion(_ id: UUID) -> String {
        "dailyFlow.home.partnerQuestion.\(id.uuidString)"
    }
}

/// Questions from earlier days that the partner answered and the user has not, shown
/// inside a daily question card as locked rows: Robin answered "**A memory that
/// stayed**" yesterday. A row shows only the question's short prompt, never the
/// partner's answer, and opens that question's answer flow.
struct LockedPartnerQuestionRows: View {
    let state: DailyChallengeCardState
    let partnerName: String
    let partnerPhotoAssetID: UUID?
    /// Set on Home so a tapped row is the source its answer flow zooms out of.
    var zoomNamespace: Namespace.ID?
    var onOpen: (UUID) -> Void = { _ in }

    var body: some View {
        if !state.lockedPartnerQuestions.isEmpty {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                ForEach(state.lockedPartnerQuestions) { question in
                    row(question)
                }

                if state.moreLockedPartnerQuestionCount > 0 {
                    Text(.dailyChallengeLockedMore(state.moreLockedPartnerQuestionCount))
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .padding(.horizontal, PaeoniaSpacing.space4)
                }
            }
        }
    }

    private func row(_ question: DailyChallengeCardState.LockedPartnerQuestion) -> some View {
        Button { onOpen(question.id) } label: {
            rowContent(question)
        }
        .buttonStyle(.plain)
        .zoomSource(DailyFlowZoom.homePartnerQuestion(question.id), in: zoomNamespace)
        .accessibilityLabel(Text(.dailyChallengeLockedA11YReady(partnerName, question.shortPrompt)))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("daily.lockedRow")
    }

    private func rowContent(_ question: DailyChallengeCardState.LockedPartnerQuestion) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            lockedAvatar

            Text(rowText(question))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .padding(PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .contentShape(Rectangle())
    }

    /// The row's sentence with the question's short prompt in bold, then the day it is
    /// from in gray, such as "yesterday".
    private func rowText(_ question: DailyChallengeCardState.LockedPartnerQuestion) -> AttributedString {
        var text = AttributedString(localized: .dailyChallengeLockedRow(partnerName, question.shortPrompt))
        // Search from the end so a partner name that contains the prompt stays plain.
        if let range = text.range(of: question.shortPrompt, options: .backwards) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        if let day = Self.dayText(daysAgo: question.daysAgo) {
            var suffix = AttributedString(" " + day)
            suffix.foregroundColor = Color.paeoniaTextTertiary
            text += suffix
        }
        return text
    }

    private static func dayText(daysAgo: Int) -> String? {
        switch daysAgo {
        case ...0: nil
        case 1: String(localized: .dailyChallengeLockedYesterday)
        default: String(localized: .dailyChallengeLockedDaysAgo(daysAgo))
        }
    }

    /// The partner's avatar with a small lock on its bottom-right edge: they answered,
    /// and the answer opens once the user answers too.
    private var lockedAvatar: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: partnerPhotoAssetID,
            name: partnerName,
            tint: .paeoniaPartnerTwo,
            size: Self.avatarSize
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "lock.fill")
                .font(.system(size: Self.lockSize * 0.55, weight: .bold))
                .foregroundStyle(.paeoniaTextInverse)
                .frame(width: Self.lockSize, height: Self.lockSize)
                .background(.paeoniaAccentPrimary, in: Circle())
                // A ring in the row's color keeps the badge apart from the photo.
                .overlay(Circle().strokeBorder(.paeoniaSurfaceSecondary, lineWidth: 1.5))
                .offset(x: 3, y: 3)
        }
        .accessibilityHidden(true)
    }

    private static let avatarSize: CGFloat = 32
    private static let lockSize: CGFloat = 16
}

#if DEBUG
#Preview("Locked rows") {
    let questions = [
        DailyChallengeCardState.LockedPartnerQuestion(id: UUID(), shortPrompt: "A memory that stayed"),
        DailyChallengeCardState.LockedPartnerQuestion(id: UUID(), shortPrompt: "Something small you love", daysAgo: 1),
    ]
    return VStack(spacing: PaeoniaSpacing.space24) {
        lockedRowsPreview(questions: questions, moreCount: 3)
        lockedRowsPreview(questions: questions, moreCount: 0)
    }
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

private func lockedRowsPreview(
    questions: [DailyChallengeCardState.LockedPartnerQuestion],
    moreCount: Int
) -> some View {
    LockedPartnerQuestionRows(
        state: DailyChallengeCardState(
            kind: .complete,
            hasEarlierQuestionsToAnswer: true,
            lockedPartnerQuestions: questions,
            moreLockedPartnerQuestionCount: moreCount
        ),
        partnerName: "Oda",
        partnerPhotoAssetID: nil
    )
}
#endif

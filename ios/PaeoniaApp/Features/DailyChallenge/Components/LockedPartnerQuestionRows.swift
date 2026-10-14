import SwiftUI

extension DailyFlowZoom {
    /// The zoom source of a locked row on the Home card. It differs from the question
    /// id, which the Questions tab list uses, so the two tabs never share a source.
    static func homePartnerQuestion(_ id: UUID) -> String {
        "dailyFlow.home.partnerQuestion.\(id.uuidString)"
    }
}

/// The partner's questions that wait for the user's answer, shown inside a daily
/// question card as locked rows: "Robin answered: A memory that stayed". A row shows
/// only the question's short prompt, never the partner's answer. Once the user's own
/// questions are done, a row opens that question's answer flow. Before that it only
/// says the partner has answered, and the card's main button stays on the user's own
/// questions.
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

    @ViewBuilder
    private func row(_ question: DailyChallengeCardState.LockedPartnerQuestion) -> some View {
        if state.lockedPartnerQuestionsAreOpenable {
            Button { onOpen(question.id) } label: {
                rowContent(question, showsChevron: true)
            }
            .buttonStyle(.plain)
            .zoomSource(DailyFlowZoom.homePartnerQuestion(question.id), in: zoomNamespace)
            .accessibilityLabel(Text(.dailyChallengeLockedA11YReady(partnerName, question.shortPrompt)))
            .accessibilityAddTraits(.isButton)
        } else {
            rowContent(question, showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(.dailyChallengeLockedA11YWaiting(partnerName, question.shortPrompt)))
        }
    }

    private func rowContent(
        _ question: DailyChallengeCardState.LockedPartnerQuestion,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            lockedAvatar

            Text(.dailyChallengeLockedRow(partnerName, question.shortPrompt))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(PaeoniaSpacing.space12)
        .background(.paeoniaSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
        .contentShape(Rectangle())
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
        DailyChallengeCardState.LockedPartnerQuestion(id: UUID(), shortPrompt: "Something small you love"),
    ]
    return VStack(spacing: PaeoniaSpacing.space24) {
        LockedPartnerQuestionRows(
            state: DailyChallengeCardState(
                kind: .complete,
                answeredCount: 2,
                totalCount: 2,
                hasAnswerablePartnerQuestions: true,
                lockedPartnerQuestions: questions,
                moreLockedPartnerQuestionCount: 3
            ),
            partnerName: "Oda",
            partnerPhotoAssetID: nil
        )
        LockedPartnerQuestionRows(
            state: DailyChallengeCardState(
                kind: .active(prompt: "x"),
                answeredCount: 0,
                totalCount: 2,
                hasAnswerablePartnerQuestions: true,
                lockedPartnerQuestions: questions
            ),
            partnerName: "Oda",
            partnerPhotoAssetID: nil
        )
    }
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif

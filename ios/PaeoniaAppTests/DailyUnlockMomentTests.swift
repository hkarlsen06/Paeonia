import Foundation
import Testing
@testable import PaeoniaApp

private enum IDs {
    static let me = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
    static let partner = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
    static let couple = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
    static let today = UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID()
    static let yesterday = UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID()
    static let stranger = UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID()
    static let dayStart = Date(timeIntervalSince1970: 1_782_432_000)
    static let dayEnd = Date(timeIntervalSince1970: 4_102_444_800)
    static let answeredAt = Date(timeIntervalSince1970: 1_782_450_000)
}

private func row(
    slot: Int,
    seededFor: UUID,
    shortPrompt: String = "A small moment today",
    coupleDay: UUID = IDs.today,
    isCurrentDay: Bool = true,
    startsAt: Date = IDs.dayStart,
    answerKinds: [DailyChallengeAnswerKind] = [.text],
    ownAnswerID: UUID? = nil,
    partnerAnswerID: UUID? = nil,
    canViewPartnerAnswer: Bool = false,
    instanceID: UUID = UUID()
) -> DailyQuestionRow {
    DailyQuestionRow(
        coupleDayID: coupleDay,
        coupleID: IDs.couple,
        localDate: isCurrentDay ? "2026-06-27" : "2026-06-26",
        effectiveLocalDate: nil,
        startsAt: startsAt,
        endsAt: IDs.dayEnd,
        instanceID: instanceID,
        seededForUserID: seededFor,
        slotNumber: slot,
        instanceStatus: "active",
        questionID: UUID(),
        questionVersionID: UUID(),
        questionKey: "key_\(slot)",
        promptEN: "Long prompt \(shortPrompt)",
        shortPromptEN: shortPrompt,
        promptNB: "Lang tekst \(shortPrompt)",
        shortPromptNB: shortPrompt,
        answerKinds: answerKinds,
        ownAnswerID: ownAnswerID,
        ownAnsweredAt: ownAnswerID == nil ? nil : IDs.answeredAt,
        partnerAnswerID: partnerAnswerID,
        partnerAnsweredAt: partnerAnswerID == nil ? nil : IDs.answeredAt,
        canViewPartnerAnswer: canViewPartnerAnswer,
        isCurrentDay: isCurrentDay
    )
}

private func snapshot(
    _ rows: [DailyQuestionRow],
    details: [DailyAnswerDetailRow] = []
) -> DailyChallengeSnapshot {
    DailyChallengeSnapshot.make(
        currentUserID: IDs.me,
        rows: rows,
        answerDetails: details,
        locale: Locale(identifier: "en_US"),
        refreshedAt: IDs.dayStart
    )
}

private func detail(
    answerID: UUID,
    by user: UUID,
    isOwn: Bool,
    picked: UUID?,
    canView: Bool = true
) -> DailyAnswerDetailRow {
    DailyAnswerDetailRow(
        coupleDayID: IDs.today,
        instanceID: UUID(),
        seededForUserID: IDs.partner,
        slotNumber: 1,
        answerUserID: user,
        answerID: answerID,
        answeredAt: IDs.answeredAt,
        isOwnAnswer: isOwn,
        canViewAnswer: canView,
        textBody: nil,
        selectedUserID: picked,
        mediaAssetIDs: []
    )
}

struct LockedPartnerQuestionTests {
    @Test func leavesOutQuestionsTheUserAlreadyAnswered() {
        let state = snapshot([
            row(slot: 1, seededFor: IDs.me, ownAnswerID: UUID()),
            row(slot: 2, seededFor: IDs.me, ownAnswerID: UUID()),
            row(
                slot: 1,
                seededFor: IDs.partner,
                shortPrompt: "Answered already",
                ownAnswerID: UUID(),
                partnerAnswerID: UUID(),
                canViewPartnerAnswer: true
            ),
        ]).homeCardState

        #expect(state.kind == .complete)
        #expect(state.lockedPartnerQuestions.isEmpty)
        #expect(state.moreLockedPartnerQuestionCount == 0)
        #expect(!state.hasAnswerablePartnerQuestions)
    }

    @Test func rowsOpenOnlyOnceOwnQuestionsAreDone() {
        let waiting = row(slot: 1, seededFor: IDs.partner, partnerAnswerID: UUID())

        let active = snapshot([
            row(slot: 1, seededFor: IDs.me),
            row(slot: 2, seededFor: IDs.me, ownAnswerID: UUID()),
            waiting,
        ]).homeCardState
        let complete = snapshot([
            row(slot: 1, seededFor: IDs.me, ownAnswerID: UUID()),
            row(slot: 2, seededFor: IDs.me, ownAnswerID: UUID()),
            waiting,
        ]).homeCardState

        #expect(active.lockedPartnerQuestions.count == 1)
        #expect(!active.lockedPartnerQuestionsAreOpenable)
        #expect(complete.lockedPartnerQuestions.count == 1)
        #expect(complete.lockedPartnerQuestionsAreOpenable)
    }
}

struct PartnerChoiceMatchTests {
    private let me = IDs.me
    private let partner = IDs.partner

    private func match(_ mine: UUID?, _ theirs: UUID?) -> PartnerChoiceMatch? {
        PartnerChoiceMatch.make(viewerID: me, partnerID: partner, viewerChoice: mine, partnerChoice: theirs)
    }

    @Test func bothPickedTheViewer() {
        #expect(match(me, me) == .bothPickedViewer)
    }

    @Test func bothPickedThePartner() {
        #expect(match(partner, partner) == .bothPickedPartner)
    }

    @Test func eachPickedThemselves() {
        #expect(match(me, partner) == .eachPickedThemselves)
    }

    @Test func eachPickedTheOther() {
        #expect(match(partner, me) == .eachPickedTheOther)
    }

    @Test func missingPickGivesNoMatch() {
        #expect(match(nil, me) == nil)
        #expect(match(me, nil) == nil)
        #expect(match(nil, nil) == nil)
    }

    @Test func pickOutsideTheCoupleGivesNoMatch() {
        #expect(match(IDs.stranger, me) == nil)
        #expect(match(me, IDs.stranger) == nil)
    }

    @Test func questionMatchNeedsBothPicksVisible() {
        let ownAnswer = UUID()
        let partnerAnswer = UUID()
        let participants = DailyChallengeParticipants(currentUserID: IDs.me, partnerUserID: IDs.partner)
        func question(partnerCanView: Bool) -> DailyChallengeQuestion? {
            snapshot(
                [
                    row(
                        slot: 1,
                        seededFor: IDs.partner,
                        answerKinds: [.partnerChoice],
                        ownAnswerID: ownAnswer,
                        partnerAnswerID: partnerAnswer,
                        canViewPartnerAnswer: partnerCanView
                    ),
                ],
                details: [
                    detail(answerID: ownAnswer, by: IDs.me, isOwn: true, picked: IDs.partner),
                    detail(
                        answerID: partnerAnswer,
                        by: IDs.partner,
                        isOwn: false,
                        picked: IDs.partner,
                        canView: partnerCanView
                    ),
                ]
            ).questions.first
        }

        #expect(question(partnerCanView: true)?.partnerChoiceMatch(participants: participants) == .bothPickedPartner)
        #expect(question(partnerCanView: false)?.partnerChoiceMatch(participants: participants) == nil)
        #expect(question(partnerCanView: true)?.partnerChoiceMatch(participants: DailyChallengeParticipants()) == nil)
    }
}

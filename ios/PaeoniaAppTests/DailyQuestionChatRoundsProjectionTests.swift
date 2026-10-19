import ExyteChat
import Foundation
import Testing
@testable import PaeoniaApp

extension DailyChatRoundsTests {
    // MARK: - Projection

    /// The row id of a person's answer on one day, which exists when the person answered.
    private func answerRowID(_ question: DailyChallengeQuestion, own: Bool) throws -> String {
        let detail = try #require(own ? question.ownAnswerDetail : question.partnerAnswerDetail)
        return DailyChatProjection.answerRowPrefix + detail.answerID.uuidString
    }

    private func round(
        _ question: DailyChallengeQuestion,
        seenByPartner: Bool = false
    ) -> DailyChatRound {
        var round = DailyChatRound(question: question, participants: participants, chatIsOpen: true)
        round = DailyChatRound(
            instanceID: round.instanceID, prompt: round.prompt, startsAt: round.startsAt, answers: round.answers,
            ownAnswerSeenByPartner: seenByPartner, waiting: round.waiting, match: round.match,
            mediaKind: round.mediaKind
        )
        return round
    }

    private func input(
        rounds: [DailyChatRound],
        messages: [DailyQuestionChatMessage] = []
    ) -> DailyChatProjection.Input {
        DailyChatProjection.Input(
            rounds: rounds, messages: messages, currentUserID: me, partnerName: "Oda", youName: "You"
        )
    }

    @Test func eachDayOpensWithItsQuestionAndMessagesFallBetweenTheDaysByTime() throws {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: 920, sharedRound: true)
        let between = message(at: 500)
        let after = message(at: 1_000)

        let projection = DailyChatProjection.make(input: input(
            rounds: [round(march), round(october)],
            messages: [after, between]
        ))

        let ids = projection.exyteMessages.map(\.id)
        #expect(ids == [
            DailyChatProjection.questionRowID(for: march.id),
            try answerRowID(march, own: true),
            try answerRowID(march, own: false),
            DailyChatProjection.rowID(for: between),
            DailyChatProjection.questionRowID(for: october.id),
            try answerRowID(october, own: true),
            try answerRowID(october, own: false),
            DailyChatProjection.rowID(for: after),
        ])
    }

    @Test func aLateAnswerToAnOldDayStaysWithThatDay() throws {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 1_000, sharedRound: true)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: 920, sharedRound: true)

        let projection = DailyChatProjection.make(input: input(rounds: [round(march), round(october)]))

        let lateAnswer = try answerRowID(march, own: false)
        #expect(projection.exyteMessages.map(\.id) == [
            DailyChatProjection.questionRowID(for: march.id),
            try answerRowID(march, own: true),
            lateAnswer,
            DailyChatProjection.questionRowID(for: october.id),
            try answerRowID(october, own: true),
            try answerRowID(october, own: false),
        ])
        // ExyteChat groups by time, so the order of the times must follow the order of the rows.
        let times = projection.exyteMessages.map(\.createdAt)
        #expect(times == times.sorted())
        // The late answer keeps its real time for display.
        #expect(projection.rowsByID[lateAnswer]?.createdAt == Date(timeIntervalSince1970: 1_000))
    }
}

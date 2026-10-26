import ExyteChat
import Foundation
import Testing
@testable import PaeoniaApp

extension DailyChatRoundsTests {
    // MARK: - Projection

    /// The row id of a person's answer on one day, which exists when the person answered.
    private func answerRowID(_ question: DailyChallengeQuestion, own: Bool) throws -> String {
        let detail = try #require(own ? question.ownAnswerDetail : question.partnerAnswerDetail)
        return ThreadChatProjection.answerRowPrefix + detail.answerID.uuidString
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
        messages: [ThreadChatMessage] = []
    ) -> ThreadChatProjection.Input {
        ThreadChatProjection.Input(
            rounds: rounds, messages: messages, currentUserID: me, partnerName: "Oda", youName: "You"
        )
    }

    @Test func eachDayOpensWithItsQuestionAndMessagesFallBetweenTheDaysByTime() throws {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: 920, sharedRound: true)
        let between = message(at: 500)
        let after = message(at: 1_000)

        let projection = ThreadChatProjection.make(input: input(
            rounds: [round(march), round(october)],
            messages: [after, between]
        ))

        let ids = projection.exyteMessages.map(\.id)
        #expect(ids == [
            ThreadChatProjection.questionRowID(for: march.id),
            try answerRowID(march, own: true),
            try answerRowID(march, own: false),
            ThreadChatProjection.rowID(for: between),
            ThreadChatProjection.questionRowID(for: october.id),
            try answerRowID(october, own: true),
            try answerRowID(october, own: false),
            ThreadChatProjection.rowID(for: after),
        ])
    }

    @Test func aMemorysChatOpensWithItsCardThenBothNotesBeforeTheMessages() {
        let first = message(at: 500)
        let second = message(at: 600)
        let header = ThreadChatHeader(
            eyebrow: "Memory",
            title: "Cabin weekend",
            detail: nil,
            photoAssetID: nil,
            notes: [ThreadChatNote(isOwn: true, body: "Mine"), ThreadChatNote(isOwn: false, body: "Theirs")]
        )
        var input = input(rounds: [], messages: [first, second])
        input.header = header

        let projection = ThreadChatProjection.make(input: input)

        let rows = projection.exyteMessages.compactMap { projection.rowsByID[$0.id] }
        let notes = rows.compactMap { row -> (body: String, isOwn: Bool)? in
            guard case let .note(note) = row.kind else { return nil }
            return (note.body, row.isCurrentUser)
        }
        #expect(rows.map(\.id).first == ThreadChatProjection.headerRowID)
        // Each note is from the person who wrote it, right after the card.
        #expect(notes.map(\.body) == ["Mine", "Theirs"])
        #expect(notes.map(\.isOwn) == [true, false])
        #expect(rows.dropFirst(3).map(\.id) == [
            ThreadChatProjection.rowID(for: first),
            ThreadChatProjection.rowID(for: second),
        ])
        // A note takes no reply, reaction or report.
        #expect(rows.dropFirst().prefix(2).allSatisfy { ThreadChatProjection.isDecorationRowID($0.id) })
        let times = projection.exyteMessages.map(\.createdAt)
        #expect(times == times.sorted())
    }

    @Test func aLateAnswerToAnOldDayStaysWithThatDay() throws {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 1_000, sharedRound: true)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: 920, sharedRound: true)

        let projection = ThreadChatProjection.make(input: input(rounds: [round(march), round(october)]))

        let lateAnswer = try answerRowID(march, own: false)
        #expect(projection.exyteMessages.map(\.id) == [
            ThreadChatProjection.questionRowID(for: march.id),
            try answerRowID(march, own: true),
            lateAnswer,
            ThreadChatProjection.questionRowID(for: october.id),
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

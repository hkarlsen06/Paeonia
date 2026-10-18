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

    @Test func aWaitingDayGetsANoteAfterItsAnswers() {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: nil, sharedRound: true)
        let rounds = [
            round(march),
            DailyChatRound(question: october, participants: participants, chatIsOpen: true),
        ]

        let projection = DailyChatProjection.make(input: input(rounds: rounds))

        let note = projection.rowsByID[DailyChatProjection.waitingRowPrefix + october.id.uuidString]
        #expect(note != nil)
        #expect(projection.rowsByID[DailyChatProjection.waitingRowPrefix + march.id.uuidString] == nil)
        #expect(projection.exyteMessages.last?.id == DailyChatProjection.waitingRowPrefix + october.id.uuidString)
        #expect(DailyChatProjection.isDecorationRowID(DailyChatProjection.waitingRowPrefix + october.id.uuidString))
    }

    @Test func aMatchLineSitsBetweenTheQuestionAndTheAnswers() {
        let first = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true)
        let withMatch = DailyChatRound(
            instanceID: first.id, prompt: first.prompt, startsAt: first.startsAt,
            answers: round(first).answers, ownAnswerSeenByPartner: false, waiting: nil,
            match: .eachPickedTheOther, celebratesMatch: true
        )

        let projection = DailyChatProjection.make(input: input(rounds: [withMatch]))

        let ids = projection.exyteMessages.map(\.id)
        #expect(ids.first == DailyChatProjection.questionRowID(for: first.id))
        #expect(ids[1] == DailyChatProjection.matchRowPrefix + first.id.uuidString)
        #expect(ids[2].hasPrefix(DailyChatProjection.answerRowPrefix))
        guard case let .partnerChoiceMatch(match, celebrationID)? = projection.rowsByID[ids[1]]?.kind else {
            Issue.record("The match line is missing")
            return
        }
        #expect(match == .eachPickedTheOther)
        #expect(celebrationID == first.id)
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

    @Test func eachDayKeepsItsOwnMediaKind() throws {
        let photo = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true, kinds: [.photo])
        let voice = day(startsAt: 900, ownAt: 910, partnerAt: 920, sharedRound: true, kinds: [.voice])
        let rounds = [photo, voice].map {
            DailyChatRound(question: $0, participants: participants, chatIsOpen: true)
        }

        let projection = DailyChatProjection.make(input: input(rounds: rounds))

        func mediaKind(_ question: DailyChallengeQuestion) throws -> DailyChallengeAnswerKind? {
            guard case let .answer(_, kind)? = projection.rowsByID[try answerRowID(question, own: true)]?.kind else {
                return nil
            }
            return kind
        }
        #expect(try mediaKind(photo) == .photo)
        #expect(try mediaKind(voice) == .voice)
    }

    @Test func readShowsOnlyOnTheAnswersNoLaterMessageOfYoursCarries() throws {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: 920, sharedRound: true)
        // Your message after March's answers carries the status there. No message of yours
        // follows October's answers, so they still read as seen.
        let mine = message(at: 500)

        let projection = DailyChatProjection.make(input: input(
            rounds: [round(march, seenByPartner: true), round(october, seenByPartner: true)],
            messages: [mine]
        ))

        let marchOwn = try answerRowID(march, own: true)
        let octoberOwn = try answerRowID(october, own: true)
        #expect(projection.rowsByID[marchOwn]?.status == nil)
        #expect(projection.rowsByID[octoberOwn]?.status == .read)
        // Without that message, both answers read as seen.
        let withoutMessage = DailyChatProjection.make(input: input(
            rounds: [round(march, seenByPartner: true), round(october, seenByPartner: true)]
        ))
        #expect(withoutMessage.rowsByID[marchOwn]?.status == .read)
        #expect(withoutMessage.rowsByID[octoberOwn]?.status == .read)
    }
}

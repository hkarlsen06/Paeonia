import ExyteChat
import Foundation
import Testing
@testable import PaeoniaApp

/// A couple has one chat per question, and the page stacks every day the question came up.
/// These tests cover how those days are found, merged, laid out, and scrolled to.
@MainActor
struct DailyChatRoundsTests {
    let me = UUID()
    let partner = UUID()
    let questionID = UUID()

    func answer(by userID: UUID, at seconds: TimeInterval, text: String? = "Hi") -> DailyQuestionAnswerDetail {
        DailyQuestionAnswerDetail(
            answerUserID: userID,
            answerID: UUID(),
            answeredAt: Date(timeIntervalSince1970: seconds),
            isOwnAnswer: userID == me,
            canViewAnswer: true,
            textBody: text,
            selectedUserID: nil,
            mediaAssetIDs: []
        )
    }

    /// One day of the question. `ownAt` and `partnerAt` are when each person answered, or nil.
    func day(
        id: UUID = UUID(),
        startsAt seconds: TimeInterval,
        ownAt: TimeInterval?,
        partnerAt: TimeInterval?,
        partnerReadable: Bool = true,
        sharedRound: Bool = false,
        kinds: [DailyChallengeAnswerKind] = [.text]
    ) -> DailyChallengeQuestion {
        let own = ownAt.map { answer(by: me, at: $0) }
        let theirs = partnerAt.map { answer(by: partner, at: $0) }
        return DailyChallengeQuestion(
            id: id,
            coupleDayID: UUID(),
            coupleID: UUID(),
            localDate: "2026-03-03",
            effectiveLocalDate: "2026-03-03",
            startsAt: Date(timeIntervalSince1970: seconds),
            endsAt: Date(timeIntervalSince1970: seconds + 86_400),
            seededForUserID: me,
            slotNumber: 1,
            status: .answered,
            questionID: questionID,
            questionVersionID: UUID(),
            questionKey: "rounds.test",
            prompt: "What made you smile?",
            shortPrompt: "A smile",
            answerKinds: kinds,
            ownAnswer: own.map { DailyQuestionAnswerSummary(id: $0.answerID, answeredAt: $0.answeredAt) },
            partnerAnswer: theirs.map { DailyQuestionAnswerSummary(id: $0.answerID, answeredAt: $0.answeredAt) },
            canViewPartnerAnswer: partnerReadable && own != nil && theirs != nil,
            ownAnswerDetail: own,
            partnerAnswerDetail: theirs.map { detail in
                partnerReadable && own != nil
                    ? detail
                    : DailyQuestionAnswerDetail(
                        answerUserID: detail.answerUserID, answerID: detail.answerID, answeredAt: detail.answeredAt,
                        isOwnAnswer: false, canViewAnswer: false, textBody: nil, selectedUserID: nil, mediaAssetIDs: []
                    )
            },
            origin: .own,
            isCurrentDay: false,
            hasSharedRound: sharedRound
        )
    }

    var participants: DailyChallengeParticipants {
        DailyChallengeParticipants(currentUserID: me, partnerUserID: partner, partnerDisplayName: "Oda")
    }

    // MARK: - Merging

    @Test func theOpenedDayStandsInUntilTheServerHasAnswered() {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 120)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: nil)

        #expect(DailyChatRounds.merged(loaded: nil, entry: october, serverConfirmed: false) == [october])
        // The phone's list is older than the opened day, and the server has not answered yet.
        let provisional = DailyChatRounds.merged(loaded: [march], entry: october, serverConfirmed: false)
        #expect(provisional.map(\.id) == [march.id, october.id])
    }

    @Test func aDayTheServerNoLongerSendsGoesAway() {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 120)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: 920)

        let merged = DailyChatRounds.merged(loaded: [march], entry: october, serverConfirmed: true)

        #expect(merged.map(\.id) == [march.id])
    }

    @Test func aPartnerAnswerTheServerWithheldStaysHiddenEvenIfTheOpenedDayHasIt() {
        let id = UUID()
        let withheld = day(id: id, startsAt: 900, ownAt: 910, partnerAt: 920, partnerReadable: false)
        let stale = day(id: id, startsAt: 900, ownAt: 910, partnerAt: 920)

        let merged = DailyChatRounds.merged(loaded: [withheld], entry: stale, serverConfirmed: true)

        #expect(merged == [withheld])
        #expect(merged.first?.partnerAnswerDetail?.canViewAnswer == false)
    }

    @Test func yourOwnAnswerShowsBeforeTheServerListHasIt() throws {
        let id = UUID()
        let serverCopy = day(id: id, startsAt: 900, ownAt: nil, partnerAt: 920)
        let entry = day(id: id, startsAt: 900, ownAt: 910, partnerAt: 920)

        let merged = try #require(
            DailyChatRounds.merged(loaded: [serverCopy], entry: entry, serverConfirmed: true).first
        )

        #expect(merged.ownAnswerDetail == entry.ownAnswerDetail)
        // The partner's answer is still the server's: hidden until the server opens it.
        #expect(merged.partnerAnswerDetail?.canViewAnswer == false)
    }

    @Test func theChatIsAvailableOnceAnyDayHasBothAnswers() {
        let alone = day(startsAt: 900, ownAt: 910, partnerAt: nil)
        let shared = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true)

        #expect(!DailyChatRounds.isChatAvailable([alone]))
        #expect(DailyChatRounds.isChatAvailable([shared, alone]))
    }

    // MARK: - Opening scroll

    func message(at seconds: TimeInterval) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: UUID(), threadID: UUID(), questionID: questionID, senderUserID: me, body: "Hey",
            createdAt: Date(timeIntervalSince1970: seconds), clientOperationID: nil, isSending: false
        )
    }

    @Test func theNewestDayOpensAtTheNewestMessageOnceSomeoneHasWrittenSinceItBegan() {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: 920, sharedRound: true)

        #expect(
            DailyChatRounds.openingScroll(rounds: [march, october], focusing: nil, messages: [message(at: 1_000)])
                == .newestMessage
        )
        // Messages from before the newest day began don't pull the page down.
        #expect(
            DailyChatRounds.openingScroll(rounds: [march, october], focusing: nil, messages: [message(at: 500)])
                == .questionRow(october.id)
        )
    }

    @Test func anEarlierDayOpensAtItsQuestionEvenWithNewerMessages() {
        let march = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true)
        let june = day(startsAt: 500, ownAt: 510, partnerAt: 520, sharedRound: true)
        let october = day(startsAt: 900, ownAt: 910, partnerAt: 920, sharedRound: true)
        let rounds = [march, june, october]

        #expect(
            DailyChatRounds.openingScroll(rounds: rounds, focusing: june.id, messages: [message(at: 1_000)])
                == .questionRow(june.id)
        )
        #expect(
            DailyChatRounds.openingScroll(rounds: rounds, focusing: march.id, messages: [message(at: 1_000)])
                == .oldestRow
        )
    }

    @Test func aSingleDayWithNothingWrittenOpensAtTheTop() {
        let only = day(startsAt: 100, ownAt: 110, partnerAt: 120, sharedRound: true)

        #expect(DailyChatRounds.openingScroll(rounds: [only], focusing: only.id, messages: []) == .oldestRow)
        let written = DailyChatRounds.openingScroll(rounds: [only], focusing: only.id, messages: [message(at: 200)])
        #expect(written == .newestMessage)
    }

    // MARK: - Round contents

    @Test func aDayWaitsForWhoeverHasNotAnswered() {
        let waitingOnPartner = day(startsAt: 900, ownAt: 910, partnerAt: nil)
        let waitingOnYou = day(startsAt: 900, ownAt: nil, partnerAt: 920)
        let waitingOnSend = day(startsAt: 900, ownAt: 910, partnerAt: 920, partnerReadable: false)
        let both = day(startsAt: 900, ownAt: 910, partnerAt: 920)

        func waiting(_ question: DailyChallengeQuestion, chatIsOpen: Bool = true) -> DailyChatRound.Waiting? {
            DailyChatRound(question: question, participants: participants, chatIsOpen: chatIsOpen).waiting
        }

        #expect(waiting(waitingOnPartner) == .partner)
        #expect(waiting(waitingOnPartner, chatIsOpen: false) == .partnerBeforeChat)
        #expect(waiting(waitingOnYou) == .yourAnswer)
        #expect(waiting(waitingOnSend) == .reveal)
        #expect(waiting(both) == nil)
    }

    @Test func aDayOnlyShowsTheAnswersTheUserMayRead() {
        let hidden = day(startsAt: 900, ownAt: nil, partnerAt: 920)
        let round = DailyChatRound(question: hidden, participants: participants, chatIsOpen: true)

        #expect(round.answers.isEmpty)
    }
}

/// One day of a question's page, as the server sends it.
struct ChatRoundDay {
    let instance: UUID
    let date: String
    let startsAt: String
}

/// The server's answer for a question's page, as the app decodes it. Every day has the
/// given instance id and couple-local date, and none has answers yet.
func decodedChatRounds(
    threadID: UUID?,
    rounds: [ChatRoundDay],
    user: UUID,
    coupleID: UUID,
    questionID: UUID
) throws -> DailyQuestionChatRoundsRow {
    func row(_ instance: UUID, date: String, startsAt: String) -> [String: Any] {
        [
            "couple_day_id": UUID().uuidString, "couple_id": coupleID.uuidString, "local_date": date,
            "starts_at": startsAt, "ends_at": startsAt, "instance_id": instance.uuidString,
            "seeded_for_user_id": user.uuidString, "slot_number": 1, "instance_status": "active",
            "question_id": questionID.uuidString, "question_version_id": UUID().uuidString,
            "question_key": "q", "prompt_en": "Prompt", "short_prompt_en": "Short", "prompt_nb": "Spørsmål",
            "short_prompt_nb": "Kort", "answer_kinds": ["text"], "own_answer_id": NSNull(),
            "own_answered_at": NSNull(), "partner_answer_id": NSNull(), "partner_answered_at": NSNull(),
            "can_view_partner_answer": false, "is_current_day": false, "chat_available": true,
            "earlier_round_count": 0, "latest_earlier_round_local_date": NSNull(),
        ]
    }
    let object: [String: Any] = [
        "thread_id": threadID?.uuidString ?? NSNull(),
        "questions": rounds.map { row($0.instance, date: $0.date, startsAt: $0.startsAt) },
        "answer_details": [Any](),
    ]
    return try PaeoniaConvexClient.decoder.decode(
        DailyQuestionChatRoundsRow.self,
        from: JSONSerialization.data(withJSONObject: object)
    )
}

struct DailyChatRoundsDecodingTests {
    @Test func theServersDaysBecomeQuestionsInTheSameOrder() throws {
        let user = UUID()
        let coupleID = UUID()
        let questionID = UUID()
        let first = UUID()
        let second = UUID()
        let threadID = UUID()
        let row = try decodedChatRounds(
            threadID: threadID,
            rounds: [
                ChatRoundDay(instance: first, date: "2026-03-03", startsAt: "2026-03-03T00:00:00.000Z"),
                ChatRoundDay(instance: second, date: "2026-10-09", startsAt: "2026-10-09T00:00:00.000Z"),
            ],
            user: user, coupleID: coupleID, questionID: questionID
        )
        let rounds = row.rounds(currentUserID: user, locale: Locale(identifier: "en"))

        #expect(row.threadID == threadID)
        #expect(row.isForCouple(coupleID))
        #expect(!row.isForCouple(UUID()))
        #expect(rounds.map(\.id) == [first, second])
        #expect(rounds.allSatisfy { $0.questionID == questionID && $0.hasSharedRound && $0.prompt == "Prompt" })
    }

    @Test func theRowSurvivesTheChatCache() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatRounds-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileDailyQuestionChatCache(directoryURL: directory)
        let user = UUID()
        let questionID = UUID()
        let row = try decodedChatRounds(
            threadID: nil,
            rounds: [ChatRoundDay(instance: UUID(), date: "2026-03-03", startsAt: "2026-03-03T00:00:00.000Z")],
            user: user, coupleID: UUID(), questionID: questionID
        )

        let generation = await cache.purgeGeneration()
        #expect(await cache.saveRounds(row, ownerUserID: user, questionID: questionID, unlessPurgedSince: generation))
        let reopened = FileDailyQuestionChatCache(directoryURL: directory)
        #expect(await reopened.rounds(ownerUserID: user, questionID: questionID) == row)
        #expect(await reopened.rounds(ownerUserID: UUID(), questionID: questionID) == nil)

        // A purge that ran after the read stops the save, and clears what was kept.
        await cache.clearAll()
        #expect(await cache.rounds(ownerUserID: user, questionID: questionID) == nil)
        let saved = await cache.saveRounds(
            row, ownerUserID: user, questionID: questionID, unlessPurgedSince: generation
        )
        #expect(!saved)
    }
}

struct DailyChallengeEarlierAnswerTests {
    private func question(earlierCount: Int, date: String?, shared: Bool) -> DailyChallengeQuestion {
        DailyChallengeQuestion(
            id: UUID(), coupleDayID: UUID(), coupleID: UUID(), localDate: "2026-10-09",
            effectiveLocalDate: "2026-10-09", startsAt: .now, endsAt: .now, seededForUserID: UUID(),
            slotNumber: 1, status: .answered, questionID: UUID(), questionVersionID: UUID(), questionKey: "k",
            prompt: "P", shortPrompt: "S", answerKinds: [.text], ownAnswer: nil, partnerAnswer: nil,
            canViewPartnerAnswer: false, ownAnswerDetail: nil, partnerAnswerDetail: nil, origin: .own,
            isCurrentDay: true, earlierRoundCount: earlierCount, latestEarlierRoundLocalDate: date,
            hasSharedRound: shared
        )
    }

    @Test func theNoteNeedsAnEarlierAnswerAndAChatToOpen() {
        let never = question(earlierCount: 0, date: nil, shared: true)
        let noChat = question(earlierCount: 1, date: "2026-03-03", shared: false)
        let both = question(earlierCount: 2, date: "2026-03-03", shared: true)
        #expect(DailyChallengeEarlierAnswer(question: never) == nil)
        #expect(DailyChallengeEarlierAnswer(question: noChat) == nil)
        #expect(DailyChallengeEarlierAnswer(question: both) != nil)
    }

    @Test func theDateShowsTheYearOnlyWhenItIsNotThisYear() throws {
        let thisYear = try #require(DailyChallengeEarlierAnswer(
            question: question(earlierCount: 1, date: "2026-03-03", shared: true)
        ))
        let now = try #require(DailyChallengeHistory.parseLocalDate("2026-10-14"))

        #expect(!thisYear.dateText(now: now).contains("2026"))
        #expect(thisYear.dateText(now: now.addingTimeInterval(400 * 86_400)).contains("2026"))
    }
}

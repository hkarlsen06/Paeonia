import CoreGraphics
import ExyteChat
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct DailyChatReceiptAndTypingRowTests {
    private let me = UUID()
    private let partner = UUID()

    private func message(_ sender: UUID, at seconds: TimeInterval) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: UUID(), threadID: UUID(), questionID: UUID(), senderUserID: sender, body: "Hi",
            createdAt: Date(timeIntervalSince1970: 1_000 + seconds), clientOperationID: nil, isSending: false
        )
    }

    private func input(
        _ messages: [DailyQuestionChatMessage],
        typing: Bool = false,
        readThrough: UUID? = nil
    ) -> DailyChatProjection.Input {
        DailyChatProjection.Input(
            rounds: [DailyChatRound(
                instanceID: UUID(), prompt: "Q", startsAt: Date(timeIntervalSince1970: 0), answers: [],
                ownAnswerSeenByPartner: false, waiting: nil, match: nil
            )],
            messages: messages,
            currentUserID: me, partnerName: "Oda", youName: "You",
            partnerIsTyping: typing, partnerLastReadMessageID: readThrough
        )
    }

    @Test func readGoesOnYourNewestReadMessageAndSentOnYourNewest() {
        let first = message(me, at: 0)
        let second = message(me, at: 10)
        let projection = DailyChatProjection.make(input: input([first, second], readThrough: first.id))

        #expect(projection.rowsByID[first.id.uuidString]?.status == .read)
        #expect(projection.rowsByID[second.id.uuidString]?.status == .sent)
    }

    @Test func readGoesOnYourAnswerOnlyUntilYouSendAMessage() {
        let answer = DailyQuestionAnswerDetail(
            answerUserID: me, answerID: UUID(), answeredAt: Date(timeIntervalSince1970: 0), isOwnAnswer: true,
            canViewAnswer: true, textBody: "Mine", selectedUserID: nil, mediaAssetIDs: []
        )
        let answerRowID = DailyChatProjection.answerRowPrefix + answer.answerID.uuidString
        func projection(_ messages: [DailyQuestionChatMessage]) -> DailyChatProjection {
            DailyChatProjection.make(input: DailyChatProjection.Input(
                rounds: [DailyChatRound(
                    instanceID: UUID(), prompt: "Q", startsAt: Date(timeIntervalSince1970: 0), answers: [answer],
                    ownAnswerSeenByPartner: true, waiting: nil, match: nil
                )],
                messages: messages,
                currentUserID: me, partnerName: "Oda", youName: "You"
            ))
        }

        #expect(projection([message(partner, at: 10)]).rowsByID[answerRowID]?.status == .read)
        #expect(projection([message(me, at: 10)]).rowsByID[answerRowID]?.status == nil)
    }
}

@MainActor
struct DailyChatPresenceModelTests {
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 10_000)
    }

    private actor TypingRecorder: DailyQuestionChatServicing {
        private(set) var typingCalls: [Bool] = []
        private(set) var readMarks: [UUID] = []

        func setTyping(coupleID _: UUID, questionID _: UUID, isTyping: Bool) { typingCalls.append(isTyping) }
        func markThreadReadOnServer(threadID _: UUID, messageID: UUID) { readMarks.append(messageID) }

        func cachedThreadSummaries(ownerUserID _: UUID) -> [DailyQuestionThreadSummary] { [] }
        func refreshThreadSummaries(ownerUserID _: UUID) throws -> [DailyQuestionThreadSummary] { [] }
        func cachedMessages(ownerUserID _: UUID, questionID _: UUID) -> [DailyQuestionChatMessage] { [] }
        func refreshMessages(ownerUserID _: UUID, questionID _: UUID, threadID _: UUID) throws
            -> [DailyQuestionChatMessage] { [] }
        func pendingMessages(
            ownerUserID _: UUID, coupleID _: UUID, questionID _: UUID
        ) -> [DailyQuestionChatMessage] { [] }
        func hasPendingThreadCreation(ownerUserID _: UUID, coupleID _: UUID, questionID _: UUID) -> Bool { false }
        func discardFailedMessage(ownerUserID _: UUID, clientOperationID _: UUID) {}
        // swiftlint:disable:next function_parameter_count
        func queueMessage(
            ownerUserID _: UUID, coupleID _: UUID, questionID _: UUID, threadID _: UUID?, body _: String,
            photos _: DailyQuestionChatPhotosPayload?, createThread _: Bool, replyToMessageID _: UUID?,
            operation _: SyncClientOperation
        ) throws -> DailyQuestionChatMessage { throw DailyQuestionChatServiceError.unavailable }
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func typingSendsOneHeartbeatEveryFewSecondsAndStopsOnAnEmptyField() async {
        let service = TypingRecorder()
        let clock = Clock()
        let model = DailyChatPresenceModel(coupleID: UUID(), questionID: UUID(), service: service, now: { clock.now })

        model.draftChanged("H")
        model.draftChanged("He")
        clock.now += 3
        model.draftChanged("Hey")
        await settle()
        #expect(await service.typingCalls == [true, true])

        model.draftChanged("")
        await settle()
        #expect(await service.typingCalls == [true, true, false])
    }

    @Test func readMarksWaitBrieflyAndSendOnceForABurst() async throws {
        let service = TypingRecorder()
        let model = DailyChatPresenceModel(coupleID: UUID(), questionID: UUID(), service: service)
        let thread = UUID()
        let first = UUID()
        let second = UUID()

        model.markRead(threadID: thread, messageID: first)
        model.markRead(threadID: thread, messageID: second)
        // Waits out the debounce, with room for a busy test run.
        for _ in 0..<60 where await service.readMarks.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(300))

        #expect(await service.readMarks == [second])
    }
}

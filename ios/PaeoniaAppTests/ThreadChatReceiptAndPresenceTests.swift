import CoreGraphics
import ExyteChat
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import PaeoniaApp

@MainActor
struct ThreadChatReceiptAndTypingRowTests {
    private let me = UUID()
    private let partner = UUID()

    private func message(_ sender: UUID, at seconds: TimeInterval) -> ThreadChatMessage {
        ThreadChatMessage(
            id: UUID(), threadID: UUID(), subjectID: UUID(), senderUserID: sender, body: "Hi",
            createdAt: Date(timeIntervalSince1970: 1_000 + seconds), clientOperationID: nil, isSending: false
        )
    }

    private func input(
        _ messages: [ThreadChatMessage],
        typing: Bool = false,
        readThrough: UUID? = nil
    ) -> ThreadChatProjection.Input {
        ThreadChatProjection.Input(
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
        let projection = ThreadChatProjection.make(input: input([first, second], readThrough: first.id))

        #expect(projection.rowsByID[first.id.uuidString]?.status == .read)
        #expect(projection.rowsByID[second.id.uuidString]?.status == .sent)
    }

    @Test func readGoesOnYourAnswerOnlyUntilYouSendAMessage() {
        let answer = DailyQuestionAnswerDetail(
            answerUserID: me, answerID: UUID(), answeredAt: Date(timeIntervalSince1970: 0), isOwnAnswer: true,
            canViewAnswer: true, textBody: "Mine", selectedUserID: nil, mediaAssetIDs: []
        )
        let answerRowID = ThreadChatProjection.answerRowPrefix + answer.answerID.uuidString
        func projection(_ messages: [ThreadChatMessage]) -> ThreadChatProjection {
            ThreadChatProjection.make(input: ThreadChatProjection.Input(
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
struct ThreadChatPresenceModelTests {
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 10_000)
    }

    private actor TypingRecorder: ThreadChatServicing {
        private(set) var typingCalls: [Bool] = []
        private(set) var readMarks: [UUID] = []
        var delaysStart = false
        private var start: CheckedContinuation<Void, Never>?
        func delayStart() { delaysStart = true }
        var startIsWaiting: Bool { start != nil }
        func finishStart() { start?.resume(); start = nil }

        func setTyping(coupleID _: UUID, subject _: ThreadChatSubject, isTyping: Bool) async {
            if isTyping, delaysStart { await withCheckedContinuation { start = $0 } }
            typingCalls.append(isTyping)
        }
        func markThreadReadOnServer(threadID _: UUID, messageID: UUID) { readMarks.append(messageID) }

        func cachedThreadSummaries(ownerUserID _: UUID) -> [ThreadChatSummary] { [] }
        func refreshThreadSummaries(ownerUserID _: UUID) throws -> [ThreadChatSummary] { [] }
        func cachedMessages(ownerUserID _: UUID, subjectID _: UUID) -> [ThreadChatMessage] { [] }
        func refreshMessages(ownerUserID _: UUID, subjectID _: UUID, threadID _: UUID) throws
            -> [ThreadChatMessage] { [] }
        func pendingMessages(
            ownerUserID _: UUID, coupleID _: UUID, subjectID _: UUID
        ) -> [ThreadChatMessage] { [] }
        func hasPendingThreadCreation(ownerUserID _: UUID, coupleID _: UUID, subjectID _: UUID) -> Bool { false }
        func discardFailedMessage(ownerUserID _: UUID, clientOperationID _: UUID) {}
        // swiftlint:disable:next function_parameter_count
        func queueMessage(
            ownerUserID _: UUID, coupleID _: UUID, subject _: ThreadChatSubject, threadID _: UUID?, body _: String,
            photos _: ThreadChatPhotosPayload?, createThread _: Bool, replyTo _: ThreadChatItemID?,
            operation _: SyncClientOperation
        ) throws -> ThreadChatMessage { throw ThreadChatServiceError.unavailable }
    }

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func stoppingWaitsForAnInFlightTypingStart() async {
        let service = TypingRecorder()
        await service.delayStart()
        let model = ThreadChatPresenceModel(coupleID: UUID(), subject: .question(UUID()), service: service)
        model.draftChanged("Hello")
        while !(await service.startIsWaiting) { await Task.yield() }
        let stop = Task { await model.stopTyping() }
        await settle()
        await service.finishStart()
        await stop.value
        #expect(await service.typingCalls == [true, false])
    }

    @Test func typingSendsOneHeartbeatEveryFewSecondsAndStopsOnAnEmptyField() async {
        let service = TypingRecorder()
        let clock = Clock()
        let model = ThreadChatPresenceModel(
            coupleID: UUID(), subject: .question(UUID()), service: service, now: { clock.now }
        )

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
        let model = ThreadChatPresenceModel(coupleID: UUID(), subject: .question(UUID()), service: service)
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

import CoreGraphics
import ExyteChat
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import PaeoniaApp

struct DailyChatProjectionTests {
    private let me = UUID()
    private let partner = UUID()
    private let threadID = UUID()
    private let questionID = UUID()
    private let instanceID = UUID()

    private func round(answers: [DailyQuestionAnswerDetail] = [], seenByPartner: Bool = false) -> DailyChatRound {
        DailyChatRound(
            instanceID: instanceID,
            prompt: "What made you smile?",
            startsAt: Date(timeIntervalSince1970: 0),
            answers: answers,
            ownAnswerSeenByPartner: seenByPartner,
            waiting: nil,
            match: nil
        )
    }

    private func message(
        _ body: String,
        from sender: UUID,
        at seconds: TimeInterval,
        isSending: Bool = false,
        replyTo: UUID? = nil
    ) -> DailyQuestionChatMessage {
        DailyQuestionChatMessage(
            id: UUID(),
            threadID: threadID,
            questionID: questionID,
            senderUserID: sender,
            body: body,
            createdAt: Date(timeIntervalSince1970: 1_000 + seconds),
            clientOperationID: nil,
            isSending: isSending,
            replyToMessageID: replyTo
        )
    }

    private func input(_ messages: [DailyQuestionChatMessage]) -> DailyChatProjection.Input {
        DailyChatProjection.Input(
            rounds: [round()],
            messages: messages,
            currentUserID: me,
            partnerName: "Oda",
            youName: "You"
        )
    }

    @Test func messagesCloseTogetherFromOnePersonJoinIntoARun() {
        let first = message("Hi", from: partner, at: 0)
        let second = message("How are you?", from: partner, at: 30)
        let later = message("Still there?", from: partner, at: 30 + DailyChatGrouping.maximumGap + 1)
        let projection = DailyChatProjection.make(input: input([first, second, later]))

        #expect(projection.rowsByID[first.id.uuidString]?.groupContext.position == .leading)
        #expect(projection.rowsByID[second.id.uuidString]?.groupContext.position == .trailing)
        #expect(projection.rowsByID[later.id.uuidString]?.groupContext.position == .standalone)
        #expect(projection.rowsByID[second.id.uuidString]?.groupContext.showsAvatar == false)
    }

    @Test func onlyYourNewestDeliveredMessageSaysSent() {
        let older = message("One", from: me, at: 0)
        let newer = message("Two", from: me, at: 10)
        let sending = message("Three", from: me, at: 20, isSending: true)
        let projection = DailyChatProjection.make(input: input([older, newer, sending]))

        #expect(projection.rowsByID[older.id.uuidString]?.status == nil)
        #expect(projection.rowsByID[newer.id.uuidString]?.status == .sent)
        #expect(projection.rowsByID[sending.id.uuidString]?.status == .sending)
    }

    @Test func aReplyQuotesItsTargetOrSaysItIsGone() {
        let original = message("Want to call later?", from: partner, at: 0)
        let reply = message("Yes!", from: me, at: 10, replyTo: original.id)
        let orphan = message("What?", from: me, at: 20, replyTo: UUID())
        let projection = DailyChatProjection.make(input: input([original, reply, orphan]))

        let quoted = projection.rowsByID[reply.id.uuidString]?.quotedPreview
        #expect(quoted?.senderName == "Oda")
        #expect(quoted?.snippet == "Want to call later?")
        #expect(projection.rowsByID[orphan.id.uuidString]?.quotedPreview?.snippet == nil)
    }

    @Test func theQuestionOpensTheListAndRowsRedrawOnlyWhenTheyChange() {
        let first = message("Hi", from: partner, at: 0)
        let same = DailyChatProjection.make(input: input([first]))
        let again = DailyChatProjection.make(input: input([first]))
        let edited = DailyChatProjection.make(input: input([
            DailyQuestionChatMessage(
                id: first.id, threadID: threadID, questionID: questionID, senderUserID: partner,
                body: "Hi there", createdAt: first.createdAt, clientOperationID: nil, isSending: false
            ),
        ]))

        #expect(same.exyteMessages.first?.id == DailyChatProjection.questionRowID(for: instanceID))
        #expect(same.exyteMessages == again.exyteMessages)
        #expect(same.exyteMessages.last != edited.exyteMessages.last)
    }

    @Test func theMenuOffersWhatEachRowAllows() {
        let partnerMessage = message("Hi", from: partner, at: 0)
        let mine = message("Hey", from: me, at: 10)
        let sending = message("Wait", from: me, at: 20, isSending: true)
        let projection = DailyChatProjection.make(input: input([partnerMessage, mine, sending]))
        func items(_ id: String) -> [DailyChatMenuAction] {
            projection.exyteMessages.first { $0.id == id }.map(DailyChatMenuAction.menuItems(for:)) ?? []
        }

        #expect(items(DailyChatProjection.questionRowID(for: instanceID)) == [.copy])
        #expect(items(partnerMessage.id.uuidString) == [.reply, .copy, .report])
        #expect(items(mine.id.uuidString) == [.reply, .copy])
        #expect(items(sending.id.uuidString) == [.copy])
    }

    @Test func yourOwnFreshTextOffersEditAndAnswersNever() {
        let answer = DailyQuestionAnswerDetail(
            answerUserID: me, answerID: UUID(), answeredAt: .now, isOwnAnswer: true,
            canViewAnswer: true, textBody: "My answer", selectedUserID: nil, mediaAssetIDs: []
        )
        let fresh = DailyQuestionChatMessage(
            id: UUID(), threadID: threadID, questionID: questionID, senderUserID: me,
            body: "Just now", createdAt: .now, clientOperationID: nil, isSending: false
        )
        let partners = DailyQuestionChatMessage(
            id: UUID(), threadID: threadID, questionID: questionID, senderUserID: partner,
            body: "Me too", createdAt: .now, clientOperationID: nil, isSending: false
        )
        let projection = DailyChatProjection.make(input: DailyChatProjection.Input(
            rounds: [round(answers: [answer])],
            messages: [fresh, partners],
            currentUserID: me,
            partnerName: "Oda",
            youName: "You"
        ))
        func items(_ id: String) -> [DailyChatMenuAction] {
            projection.exyteMessages.first { $0.id == id }.map(DailyChatMenuAction.menuItems(for:)) ?? []
        }

        #expect(items(fresh.id.uuidString) == [.reply, .edit, .copy])
        #expect(!items(partners.id.uuidString).contains(.edit))
        #expect(!items(DailyChatProjection.answerRowPrefix + answer.answerID.uuidString).contains(.edit))
    }

    @Test func anEditRedrawsTheRow() {
        let original = message("Hi", from: me, at: 0)
        var edited = original
        edited.editedAt = Date(timeIntervalSince1970: 1_100)
        let before = DailyChatProjection.make(input: input([original]))
        let after = DailyChatProjection.make(input: input([edited]))

        #expect(before.exyteMessages.last?.triggerRedraw != after.exyteMessages.last?.triggerRedraw)
    }
}

struct DailyChatGestureResolverTests {
    @Test func aReplySwipeFollowsTheFingerThenResists() {
        let resolver = DailyChatReplySwipeResolver.self
        #expect(resolver.clampedOffset(horizontal: 40, vertical: 5, allowedDirection: .right) == 40)
        #expect(resolver.clampedOffset(horizontal: -40, vertical: 5, allowedDirection: .right) == 0)
        #expect(resolver.clampedOffset(horizontal: 10, vertical: 40, allowedDirection: .right) == nil)
        #expect(resolver.clampedOffset(horizontal: 180, vertical: 0, allowedDirection: .right) == 110)
    }

    @Test func aReplyTriggersPastTheThresholdOrWithAFlick() {
        let resolver = DailyChatReplySwipeResolver.self
        #expect(resolver.outcome(offset: 40, velocity: 0, allowedDirection: .right) == .trigger)
        #expect(resolver.outcome(offset: 10, velocity: 0, allowedDirection: .right) == .reset)
        #expect(resolver.outcome(offset: -10, velocity: -400, allowedDirection: .left) == .trigger)
    }

    @Test func timesSlideInOnlyWhenSwipingLeft() {
        let resolver = DailyChatTimestampRevealResolver.self
        #expect(resolver.clampedRevealOffset(horizontal: -30, vertical: 2) == 30)
        #expect(resolver.clampedRevealOffset(horizontal: -300, vertical: 2) == resolver.revealWidth)
        #expect(resolver.clampedRevealOffset(horizontal: 30, vertical: 2) == 0)
    }

    @Test func aRightSwipeGoesBackWhenItIsFarOrFastEnough() {
        let resolver = DailyChatPanGestureResolver.self
        #expect(resolver.shouldTriggerNavigationBack(translation: CGSize(width: 80, height: 10), velocity: .zero))
        #expect(resolver.shouldTriggerNavigationBack(
            translation: CGSize(width: 20, height: 0),
            velocity: CGSize(width: 500, height: 0)
        ))
        #expect(!resolver.shouldTriggerNavigationBack(translation: CGSize(width: 40, height: 80), velocity: .zero))
    }
}

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

    @Test func aReadNewestMessageOnlySaysRead() {
        let mine = message(me, at: 0)
        let theirs = message(partner, at: 10)
        let projection = DailyChatProjection.make(input: input([mine, theirs], readThrough: theirs.id))

        #expect(projection.rowsByID[mine.id.uuidString]?.status == .read)
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

    @Test func theTypingDotsCloseTheListAndJoinThePartnersLastMessage() throws {
        let theirs = message(partner, at: 0)
        let projection = DailyChatProjection.make(input: input([theirs], typing: true))

        #expect(projection.exyteMessages.last?.id == DailyChatProjection.typingRowID)
        #expect(projection.rowsByID[DailyChatProjection.typingRowID]?.groupContext.position == .trailing)
        #expect(projection.rowsByID[theirs.id.uuidString]?.groupContext.position == .leading)
        let typingRow = try #require(projection.exyteMessages.last)
        #expect(DailyChatMenuAction.menuItems(for: typingRow).isEmpty)
    }

    @Test func theDotsStandAloneAfterYourOwnMessage() {
        let mine = message(me, at: 0)
        let projection = DailyChatProjection.make(input: input([mine], typing: true))

        #expect(projection.rowsByID[DailyChatProjection.typingRowID]?.groupContext.position == .standalone)
    }

    @Test func photosFitAFixedFrame() {
        #expect(DailyChatPhotoLayout.frameSize(for: DailyQuestionChatPhoto(width: 4_000, height: 3_000))
            == CGSize(width: 220, height: 165))
        #expect(DailyChatPhotoLayout.frameSize(for: DailyQuestionChatPhoto(width: 1_000, height: 4_000))
            == CGSize(width: 120, height: 220))
        #expect(DailyChatPhotoLayout.frameSize(for: DailyQuestionChatPhoto()) == CGSize(width: 180, height: 180))
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

    @Test func thePartnersDotsShowWhileTheyTypeAndHideWhenTheirMessageArrives() {
        let model = DailyChatPresenceModel(coupleID: UUID(), questionID: UUID(), service: TypingRecorder())

        model.apply(DailyChatPresence(partnerIsTyping: true))
        #expect(model.partnerIsTyping)

        model.partnerMessageArrived()
        #expect(!model.partnerIsTyping)
    }

    @Test func aReadMarkWhileThePartnerStillTypesDoesNotBringBackHiddenDots() {
        let model = DailyChatPresenceModel(coupleID: UUID(), questionID: UUID(), service: TypingRecorder())

        model.apply(DailyChatPresence(partnerIsTyping: true))
        model.partnerMessageArrived()
        model.apply(DailyChatPresence(partnerIsTyping: true, partnerLastReadMessageID: UUID()))

        #expect(!model.partnerIsTyping)
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

@MainActor
struct DailyChatRowGestureAreaTests {
    private func makeRow(body: String, me: UUID) -> DailyChatRow {
        let message = DailyQuestionChatMessage(
            id: UUID(),
            threadID: UUID(),
            questionID: UUID(),
            senderUserID: me,
            body: body,
            createdAt: Date(timeIntervalSince1970: 1_000),
            clientOperationID: nil,
            isSending: false
        )
        return DailyChatRow(
            id: message.id.uuidString,
            kind: .message(message),
            isCurrentUser: true,
            createdAt: message.createdAt,
            groupContext: DailyChatGroupContext(position: .standalone, isCurrentUser: true),
            status: nil,
            quotedPreview: nil
        )
    }

    private func makeMessageRowView(for row: DailyChatRow, me: UUID) -> DailyChatMessageRow {
        DailyChatMessageRow(
            row: row,
            participants: DailyChallengeParticipants(currentUserID: me, partnerDisplayName: "Oda"),
            isHighlighted: false,
            onReply: {},
            onRetry: {},
            onTapQuoted: { _ in },
            timestampReveal: DailyChatTimestampReveal(),
            messageFrame: nil
        )
    }

    /// Lays a row out in a phone-sized window and returns the width of each swipe area.
    private func swipeAreaWidths(for body: String) async throws -> (reply: CGFloat, times: CGFloat) {
        let me = UUID()
        let view = makeMessageRowView(for: makeRow(body: body, me: me), me: me)
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 200)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        // The row measures itself, then sizes the times area from that.
        for _ in 0 ..< 5 {
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        let targets = gestureTargets(in: host.view)
        let reply = targets.first { if case .replyPayload = $0.kind { true } else { false } }
        let times = targets.first { if case .timestampRevealGutter = $0.kind { true } else { false } }
        return (reply?.bounds.width ?? 0, times?.bounds.width ?? 0)
    }

    private func gestureTargets(in view: UIView) -> [DailyChatGestureTargetView] {
        let own = (view as? DailyChatGestureTargetView).map { [$0] } ?? []
        return own + view.subviews.flatMap(gestureTargets)
    }

    @Test(.timeLimit(.minutes(1))) func aShortOwnMessageLeavesTheSpaceBesideItForTheTimes() async throws {
        let widths = try await swipeAreaWidths(for: "Hi")
        #expect(widths.reply > 0)
        #expect(widths.reply < 100)
        #expect(widths.times > 250)
    }
}

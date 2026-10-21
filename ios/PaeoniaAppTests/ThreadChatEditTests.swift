import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct ThreadChatEditTests {
    private func ownMessage(
        _ fixture: ChatTestFixture,
        sentAgo seconds: TimeInterval = 30
    ) -> ThreadChatMessage {
        ThreadChatMessage(
            id: fixture.messageID,
            threadID: fixture.threadID,
            subjectID: fixture.question.questionID,
            senderUserID: fixture.ownerUserID,
            body: "Se you soon",
            createdAt: Date.now.addingTimeInterval(-seconds),
            clientOperationID: nil,
            isSending: false
        )
    }

    @Test func onlyYourOwnSentTextInsideFiveMinutesCanBeEdited() {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        let fresh = ownMessage(fixture)
        let partners = ThreadChatMessage(
            id: UUID(), threadID: fresh.threadID, subjectID: fresh.subjectID,
            senderUserID: fixture.partnerUserID, body: "Hi", createdAt: fresh.createdAt,
            clientOperationID: nil, isSending: false
        )
        var voice = fresh
        voice.voice = ThreadChatVoice(mediaAssetID: UUID(), durationMs: 1_000)

        #expect(viewModel.canEdit(fresh))
        #expect(!viewModel.canEdit(ownMessage(fixture, sentAgo: ThreadChatMessage.editWindow + 1)))
        #expect(!viewModel.canEdit(partners))
        #expect(!viewModel.canEdit(voice))
    }

    @Test func savingSendsTheNewTextAndEndsTheEdit() async {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        let message = ownMessage(fixture)

        viewModel.startEditing(message)
        #expect(viewModel.editTarget?.id == message.id)

        #expect(await viewModel.saveEdit("  See you soon  ") == .saved)
        #expect(await fixture.gateway.lastEdit?.body == "See you soon")
        #expect(await fixture.gateway.lastEdit?.messageID == message.id)
        #expect(viewModel.editTarget == nil)
    }

    @Test func aFailedSaveKeepsEditingAndSaysSo() async {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await fixture.gateway.setFailure(true)
        viewModel.startEditing(ownMessage(fixture))

        #expect(await viewModel.saveEdit("See you soon") == .failed)
        #expect(viewModel.editTarget != nil)
        #expect(viewModel.notice == .editFailed(.other))
    }

    @Test func theServerClosingTheWindowEndsTheEdit() async {
        let fixture = ChatTestFixture()
        let viewModel = fixture.makeViewModel()
        await fixture.gateway.setEditError(EditWindowServerError())
        viewModel.startEditing(ownMessage(fixture))

        #expect(await viewModel.saveEdit("See you soon") == .windowClosed)
        #expect(viewModel.editTarget == nil)
        #expect(viewModel.notice == .editWindowClosed)
    }

    /// Reads like the server's refusal once the error is turned into text.
    private struct EditWindowServerError: Error, CustomStringConvertible {
        var description: String { "23514 messages can only be edited for 5 minutes after sending" }
    }
}

struct ThreadChatMergeTests {
    @Test func mergeOrdersMessagesAndKeepsOneCopyPerOperation() throws {
        let subjectID = UUID()
        let senderID = UUID()
        let operationID = UUID()
        let first = ThreadChatMessage(
            id: UUID(),
            threadID: UUID(),
            subjectID: subjectID,
            senderUserID: senderID,
            body: "First",
            createdAt: Date(timeIntervalSince1970: 1),
            clientOperationID: nil,
            isSending: false
        )
        let confirmed = ThreadChatMessage(
            id: UUID(),
            threadID: UUID(),
            subjectID: subjectID,
            senderUserID: senderID,
            body: "Second",
            createdAt: Date(timeIntervalSince1970: 2),
            clientOperationID: operationID,
            isSending: false
        )
        let optimistic = ThreadChatMessage(
            id: operationID,
            threadID: nil,
            subjectID: subjectID,
            senderUserID: senderID,
            body: "Second",
            createdAt: Date(timeIntervalSince1970: 2),
            clientOperationID: operationID,
            isSending: true
        )

        let merged = ThreadChatMessage.visibleOrdered(
            remote: [confirmed, first],
            optimistic: [optimistic]
        )

        #expect(merged.map(\.body) == ["First", "Second"])
    }
}

struct ThreadChatReadMarkTests {
    private let me = UUID()
    private let partner = UUID()
    private let sentAt = Date(timeIntervalSince1970: 1_000)

    private func summary(threadID: UUID = UUID(), sender: UUID?) -> ThreadChatSummary {
        ThreadChatSummary(
            threadID: threadID,
            coupleID: UUID(),
            subject: .question(UUID()),
            createdAt: sentAt,
            updatedAt: sentAt,
            lastMessageID: sender == nil ? nil : UUID(),
            lastMessageAt: sender == nil ? nil : sentAt,
            lastMessageSenderUserID: sender,
            lastMessageBody: sender == nil ? nil : "Hi"
        )
    }

    @Test func onlyAPartnerMessageNewerThanTheReadMarkIsUnread() {
        let fromPartner = summary(sender: partner)

        #expect(fromPartner.isUnread(by: me, readThrough: nil))
        #expect(fromPartner.isUnread(by: me, readThrough: sentAt.addingTimeInterval(-1)))
        #expect(!fromPartner.isUnread(by: me, readThrough: sentAt))
        #expect(!summary(sender: me).isUnread(by: me, readThrough: nil))
        #expect(!summary(sender: nil).isUnread(by: me, readThrough: nil))
    }

    @Test func theFileCacheKeepsTheNewestReadMarkUntilAPurge() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatReadMarks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileThreadChatCache(directoryURL: directory)
        let threadID = UUID()

        #expect(await cache.markRead(ownerUserID: me, threadID: threadID, through: sentAt))
        let movedBack = await cache.markRead(ownerUserID: me, threadID: threadID, through: sentAt - 5)
        #expect(!movedBack)
        let reopened = FileThreadChatCache(directoryURL: directory)
        #expect(await reopened.readMarks(ownerUserID: me) == [threadID: sentAt])
        #expect(await cache.readMarks(ownerUserID: partner).isEmpty)

        await cache.clearAll()
        #expect(await cache.readMarks(ownerUserID: me).isEmpty)
    }

    @Test func aSavedReadMarkKeepsTheServerMilliseconds() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatReadMarks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let threadID = UUID()
        let serverTime = try PaeoniaConvexClient.decoder.decode(
            Date.self,
            from: Data(#""2026-10-11T12:00:00.456Z""#.utf8)
        )

        await FileThreadChatCache(directoryURL: directory)
            .markRead(ownerUserID: me, threadID: threadID, through: serverTime)
        let readThrough = await FileThreadChatCache(directoryURL: directory).readMarks(ownerUserID: me)[threadID]

        // The thread list from the server carries the same milliseconds, so the chat stays read.
        #expect(readThrough == serverTime)
    }

    @Test func aReadOnAnotherDeviceClearsTheUnreadMark() {
        var fromPartner = summary(sender: partner)
        fromPartner.viewerReadThroughAt = sentAt

        #expect(!fromPartner.isUnread(by: me, readThrough: nil))
        #expect(!fromPartner.isUnread(by: me, readThrough: sentAt - 5))
    }

    @Test func theFileCacheKeepsSeenPartnerAnswersUntilAPurge() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatReadMarks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileThreadChatCache(directoryURL: directory)
        let instanceID = UUID()

        #expect(await cache.markPartnerAnswerSeen(ownerUserID: me, instanceID: instanceID))
        let markedAgain = await cache.markPartnerAnswerSeen(ownerUserID: me, instanceID: instanceID)
        #expect(!markedAgain)
        let reopened = FileThreadChatCache(directoryURL: directory)
        #expect(await reopened.seenPartnerAnswers(ownerUserID: me) == [instanceID])
        #expect(await cache.seenPartnerAnswers(ownerUserID: partner).isEmpty)

        await cache.clearAll()
        #expect(await cache.seenPartnerAnswers(ownerUserID: me).isEmpty)
    }
}

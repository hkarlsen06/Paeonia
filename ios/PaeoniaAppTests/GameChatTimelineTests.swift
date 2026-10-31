import ExyteChat
import Foundation
import Testing

@testable import PaeoniaApp

@MainActor
struct GameChatTimelineTests {
    private let coupleID = UUID()
    private let ownerID = UUID()
    private var subject: GameChatSubject { GameChatSubject(coupleID: coupleID, kind: .mindMeld) }

    @Test func resultReplySurvivesFirstSendOutboxAndWireEncoding() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let source = GameConversationSource.mindMeld(UUID())
        let operation = fixture.operationProvider.makeOperation()
        let queued = try await service.queueMessage(
            ownerUserID: ownerID, coupleID: coupleID,
            subject: .game(subject), threadID: nil, body: "That was close", photos: nil,
            createThread: true, replyTo: .gameResult(source), operation: operation)
        #expect(queued.replyTo == .gameResult(source))
        let pending = try await fixture.pendingStore.inFlightOperations(
            ownerUserID: ownerID,
            kind: .createChatThreadWithMessage)
        let data = try #require(pending.first?.requestData)
        let payload = try JSONDecoder().decode(CreateChatThreadPayload.self, from: data)
        #expect(payload.replyToGameResultSource == source)
        let restored = await service.pendingMessages(
            ownerUserID: ownerID, coupleID: coupleID, subjectID: subject.id)
        #expect(restored.first?.replyTo == .gameResult(source))
        let request = CreateThreadMessageRequest(
            payload: payload, mediaAssetIDs: [], operation: operation)
        let json = try #require(
            JSONSerialization.jsonObject(with: PaeoniaConvexClient.encoder.encode(request))
                as? [String: Any])
        #expect(json["p_game_kind"] as? String == "mind_meld")
        #expect(json["p_source"] == nil)
        let reply = try #require(json["p_reply_to_game_result_source"] as? [String: Any])
        #expect((reply["id"] as? String)?.lowercased() == source.id.uuidString.lowercased())
        #expect(ThreadChatItemID.gameResult(source).reactionTarget == nil)
        let send = SendThreadMessageRequest(
            threadID: UUID(), body: "Again", mediaAssetIDs: [],
            replyTo: .gameResult(source), operation: operation)
        let sentJSON = try #require(
            JSONSerialization.jsonObject(with: PaeoniaConvexClient.encoder.encode(send))
                as? [String: Any])
        #expect(sentJSON["p_reply_to_game_result_source"] != nil)
        #expect(sentJSON["p_reply_to_message_id"] == nil)
        #expect(sentJSON["p_reply_to_answer_id"] == nil)
    }

    @Test func timelineOrdersTiesAndContinuesAcrossAResultOnlyPage() throws {
        let at = Date(timeIntervalSince1970: 100)
        let message = message(at: at)
        let source = GameConversationSource.mindMeld(UUID())
        let reference = GameChatResultReference(source: source, finishedAt: at, key: "0000000000000007")
        let resultPage = GameChatTimeline(
            messages: [], results: [reference], hasMore: true,
            nextBefore: .init(at: at, itemKind: "result", key: reference.key))
        let messagePage = GameChatTimeline(messages: [message], results: [], hasMore: false)
        let timeline = resultPage.merging(messagePage, older: true)
        #expect(timeline.messages == [message])
        #expect(timeline.results == [reference])
        #expect(!timeline.hasMore)
        let projection = ThreadChatProjection.make(
            input: .init(
                rounds: [], messages: timeline.messages, currentUserID: ownerID, partnerName: "Robin",
                youName: "You",
                gameResults: [
                    .init(reference: reference, result: nil, isExpanded: false, loadState: .loading)
                ]))
        #expect(
            projection.exyteMessages.map(\.id) == [
                ThreadChatProjection.rowID(for: message),
                ThreadChatProjection.gameResultRowID(reference.id),
            ])
    }

    @Test func refreshingRemovesDeletedResultsAndDisjointPagesDoNotLeaveAGap() {
        let old = result(at: 10)
        let newest = result(at: 20)
        let cached = GameChatTimeline(
            messages: [], results: [old, newest], hasMore: true,
            nextBefore: .init(at: old.finishedAt, itemKind: "result", key: old.key))
        let refreshed = cached.merging(
            .init(messages: [], results: [old], hasMore: false), older: false)
        #expect(refreshed.results == [old])
        let distant = result(at: 200)
        let disjoint = cached.merging(
            .init(
                messages: [], results: [distant], hasMore: true,
                nextBefore: .init(at: distant.finishedAt, itemKind: "result", key: distant.key)),
            older: false)
        #expect(disjoint.results == [distant])
        #expect(disjoint.nextBefore?.at == distant.finishedAt)
    }

    @Test func anOlderResultOutsideANewPageIsNotAConfirmedDeletion() {
        let old = result(at: 10)
        let newest = result(at: 200)
        let page = GameChatTimeline(
            messages: [], results: [newest], hasMore: true,
            nextBefore: .init(at: newest.finishedAt, itemKind: "result", key: newest.key))
        #expect(!page.confirmsRemoval(of: old))
        #expect(!page.confirmsRemoval(of: newest))
        #expect(GameChatTimeline.empty.confirmsRemoval(of: old))
    }

    @Test func aLiveRemovalClearsCachedDetailsAndKeepsUnrelatedMessages() async throws {
        let fixture = ChatTestFixture()
        let service = fixture.makeService()
        let source = GameConversationSource.mindMeld(UUID())
        let result = GameConversationResult.mindMeld(
            RemoteMindMeldHistoryGame(
                id: source.id, gameNumber: 1, state: .melded, endReason: nil, endedByUserID: nil,
                createdAt: .distantPast, endedAt: .distantPast, meldNumber: 1, rounds: []))
        await service.keepGameResult(result, ownerUserID: ownerID, source: source)
        let message = fixture.remoteMessage(body: "Keep this conversation")
        await fixture.cache.saveMessages([message], ownerUserID: ownerID, subjectID: subject.id)
        await fixture.gateway.setGameResultUpdates([nil])
        for await _ in service.liveGameResultUpdates(ownerUserID: ownerID, coupleID: coupleID, source: source) {
            break
        }
        #expect(await service.cachedGameResult(ownerUserID: ownerID, source: source) == nil)
        #expect(await service.cachedMessages(ownerUserID: ownerID, subjectID: subject.id) == [message])
    }

    @Test func timelineAndResultRepliesPersistByOwnerAndCannotReturnAfterPurge() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileThreadChatCache(directoryURL: directory)
        let reference = result(at: 10)
        var sent = message(at: Date(timeIntervalSince1970: 20))
        sent.replyTo = .gameResult(reference.source)
        let timeline = GameChatTimeline(
            messages: [sent], results: [reference], hasMore: true,
            nextBefore: .init(at: reference.finishedAt, itemKind: "result", key: reference.key))
        let generation = await cache.purgeGeneration()
        #expect(
            await cache.saveGameTimeline(
                timeline, ownerUserID: ownerID, subjectID: subject.id,
                older: false, unlessPurgedSince: generation))
        let reopened = FileThreadChatCache(directoryURL: directory)
        #expect(await reopened.gameTimeline(ownerUserID: ownerID, subjectID: subject.id) == timeline)
        #expect(await reopened.gameTimeline(ownerUserID: UUID(), subjectID: subject.id) == nil)
        await cache.clearAll()
        #expect(
            await cache.saveGameTimeline(
                timeline, ownerUserID: ownerID, subjectID: subject.id,
                older: false, unlessPurgedSince: generation) == false)
        #expect(await cache.gameTimeline(ownerUserID: ownerID, subjectID: subject.id) == nil)
    }

    private func result(at time: TimeInterval) -> GameChatResultReference {
        let source = GameConversationSource.mindMeld(UUID())
        return .init(
            source: source, finishedAt: Date(timeIntervalSince1970: time),
            key: source.id.uuidString.lowercased())
    }

    private func message(at date: Date) -> ThreadChatMessage {
        ThreadChatMessage(
            id: UUID(), threadID: UUID(), subjectID: subject.id, senderUserID: ownerID,
            body: "Hello", createdAt: date, clientOperationID: nil, isSending: false)
    }
}

import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct MediaAlternativeEditingTests {
    @Test func queuedVoiceCorrectionSurvivesRepositoryReopeningAndKeepsAudioAndMessageTime() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        let message = fixture.message
        await fixture.chat.saveMessages([message], ownerUserID: fixture.owner, subjectID: message.subjectID)
        let edit = fixture.edit("Corrected transcript")
        try await fixture.queue(edit)

        let reopened = FileThreadChatCache(directoryURL: fixture.directory.appendingPathComponent("chat"))
        let cached = await reopened.messages(ownerUserID: fixture.owner, subjectID: message.subjectID)
        #expect(cached.first?.voice?.transcript == edit.text)
        #expect(cached.first?.voice?.data == message.voice?.data)
        #expect(cached.first?.createdAt == message.createdAt)
        #expect(cached.first?.body == message.body)
        let reopenedService = MediaAlternativeEditingService(
            pending: SwiftDataPendingSyncOperationRepository(container: fixture.localStore.container),
            cache: fixture.caches
        )
        #expect(try await reopenedService.pendingEdit(ownerUserID: fixture.owner, coupleID: fixture.couple,
                                                     target: edit.target)?.text == edit.text)
        #expect(try await reopenedService.pendingEdit(ownerUserID: UUID(), coupleID: fixture.couple,
                                                     target: edit.target) == nil)
        #expect(try await reopenedService.pendingEdit(ownerUserID: fixture.owner, coupleID: UUID(),
                                                     target: edit.target) == nil)
    }

    @Test func lateAcceptedCorrectionCannotReplaceANewerQueuedCorrection() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        await fixture.chat.saveMessages(
            [fixture.message], ownerUserID: fixture.owner, subjectID: fixture.message.subjectID
        )
        try await fixture.queue(fixture.edit("Earlier correction"))
        let operation = try #require(try await fixture.pending.inFlightOperations(
            ownerUserID: fixture.owner, kind: .updateMediaAlternative
        ).first)
        let gateway = HoldingMediaAlternativeGateway()
        let handler = MediaAlternativePendingOperationHandler(gateway: gateway, cache: fixture.caches)
        let send = Task { try await handler.send(operation, context: fixture.context) }
        await gateway.waitForRequest()
        let laterOperation = SyncClientOperation(
            clientID: operation.operation.clientID, clientSequence: operation.operation.clientSequence + 1,
            localCreatedAt: operation.operation.localCreatedAt.addingTimeInterval(-60)
        )
        try await fixture.service.queue(fixture.edit("Latest correction"), ownerUserID: fixture.owner,
                                        operation: laterOperation,
                                        stamp: await fixture.caches.stamp(ownerUserID: fixture.owner))
        await gateway.release()
        #expect(try await send.value == .succeeded)
        let cached = await fixture.chat.messages(ownerUserID: fixture.owner, subjectID: fixture.message.subjectID)
        #expect(cached.first?.voice?.transcript == "Latest correction")
        #expect(try await fixture.service.pendingEdit(ownerUserID: fixture.owner, coupleID: fixture.couple,
                                                      target: fixture.target)?.text == "Latest correction")
    }

    @Test func privacyPurgeRefusesAnOldEditorAndALateNetworkResponse() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        let oldStamp = await fixture.caches.stamp(ownerUserID: fixture.owner)
        await fixture.chat.clearAll()
        await #expect(throws: MediaAlternativeEditingError.self) {
            try await fixture.service.queue(fixture.edit("Must not return"), ownerUserID: fixture.owner,
                                             operation: fixture.operations.makeOperation(), stamp: oldStamp)
        }
        #expect(try await fixture.pending.inFlightOperations(
            ownerUserID: fixture.owner, kind: .updateMediaAlternative
        ).isEmpty)

        await fixture.chat.saveMessages(
            [fixture.message], ownerUserID: fixture.owner, subjectID: fixture.message.subjectID
        )
        try await fixture.queue(fixture.edit("In flight"))
        let operation = try #require(try await fixture.pending.inFlightOperations(
            ownerUserID: fixture.owner, kind: .updateMediaAlternative
        ).first)
        let gateway = HoldingMediaAlternativeGateway()
        let handler = MediaAlternativePendingOperationHandler(gateway: gateway, cache: fixture.caches)
        let send = Task { try await handler.send(operation, context: fixture.context) }
        await gateway.waitForRequest()
        await fixture.chat.clearAll()
        await gateway.release()
        #expect(try await send.value == .succeeded)
        #expect(await fixture.chat.messages(ownerUserID: fixture.owner, subjectID: fixture.message.subjectID).isEmpty)
    }

    @Test func storyCorrectionAndClearPersistSeparatelyFromCaption() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        let story = Story(id: UUID(), authorUserID: fixture.owner, mediaAssetID: UUID(), caption: "Same caption",
                          accessibilityText: "Earlier description", createdAt: Date())
        await fixture.stories.save(StoriesSnapshot(stories: [story]), ownerUserID: fixture.owner)
        try await fixture.queue(MediaAlternativeEdit(
            coupleID: fixture.couple, target: .story(storyID: story.id), text: "Two red mugs"
        ))
        let reopened = FileStoriesCache(directoryURL: fixture.directory.appendingPathComponent("stories"))
        #expect(await reopened.snapshot(ownerUserID: fixture.owner).stories.first?.accessibilityText == "Two red mugs")
        #expect(await reopened.snapshot(ownerUserID: fixture.owner).stories.first?.caption == "Same caption")
        try await fixture.queue(MediaAlternativeEdit(
            coupleID: fixture.couple, target: .story(storyID: story.id), text: ""
        ))
        #expect(await fixture.stories.snapshot(ownerUserID: fixture.owner).stories.first?.accessibilityText == nil)
        #expect(try await fixture.service.pendingEdit(ownerUserID: fixture.owner, coupleID: fixture.couple,
                                                      target: .story(storyID: story.id))?.text.isEmpty == true)
    }

    @Test func aLateCacheWriterCannotReplaceANewerSameClientCorrectionAfterAClockChange() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        await fixture.chat.saveMessages(
            [fixture.message], ownerUserID: fixture.owner, subjectID: fixture.message.subjectID
        )
        let earlier = fixture.operations.makeOperation()
        let later = SyncClientOperation(clientID: earlier.clientID, clientSequence: earlier.clientSequence + 1,
                                        localCreatedAt: earlier.localCreatedAt.addingTimeInterval(-60))
        let stamp = await fixture.caches.stamp(ownerUserID: fixture.owner)
        try await fixture.caches.apply(fixture.edit("Latest"), ownerUserID: fixture.owner,
                                       operation: later, stamp: stamp)
        try await fixture.caches.apply(fixture.edit("Earlier"), ownerUserID: fixture.owner,
                                    operation: earlier, stamp: stamp)
        let messages = await fixture.chat.messages(ownerUserID: fixture.owner, subjectID: fixture.message.subjectID)
        #expect(messages.first?.voice?.transcript == "Latest")
    }

    @Test func cachedDailyCorrectionNeverFillsAHiddenPartnerAnswer() {
        let owner = UUID()
        let partner = UUID()
        let answerID = UUID()
        let hidden = DailyAnswerDetailRow(
            coupleDayID: UUID(), instanceID: UUID(), answerUserID: partner, answerID: answerID,
            answeredAt: Date(), isOwnAnswer: false, canViewAnswer: false, textBody: nil,
            selectedUserID: nil, mediaAssetIDs: []
        )
        #expect(hidden.applyingMediaAlternative(answerID: answerID, text: "Private", ownerUserID: owner) == hidden)
    }

    @Test func aPendingReadFailureBlocksStaleEditingAndRetryKeepsAuthoredText() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        try await fixture.queue(fixture.edit("Queued correction"))
        let storage = ReadFailingMediaAlternativeOutbox(base: fixture.pending)
        await storage.failReads(true)
        let model = MediaAlternativeEditorModel(
            target: fixture.target,
            context: ThreadChatContext(coupleID: fixture.couple,
                                       participants: DailyChallengeParticipants(currentUserID: fixture.owner)),
            service: MediaAlternativeEditingService(pending: storage, cache: fixture.caches)
        )
        let observer = Task { await model.observe() }
        defer { observer.cancel() }
        #expect(await waitForMain { model.pendingReadFailed })
        #expect(!model.canEdit)
        model.open(currentText: "Older server text")
        #expect(!model.isPresented)
        await storage.failReads(false)
        await model.reloadPending()
        #expect(model.canEdit)
        model.open(currentText: "Older server text")
        #expect(model.text == "Queued correction")
        model.text = "Unsent correction in the editor"
        await storage.failReads(true)
        await model.reloadPending()
        #expect(!model.canEdit)
        #expect(model.text == "Unsent correction in the editor")
        await storage.failReads(false)
        await model.reloadPending()
        #expect(model.canEdit)
        #expect(model.text == "Unsent correction in the editor")
    }

    @Test func aPrivacyPurgeAtomicallyRefusesAStaleMetadataEnqueueWithoutChangingOtherWrites() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: fixture.owner)
        let suite = "MediaAlternativePurge-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let purge = LocalPrivacyPurgeService(
            recordStore: SwiftDataLocalPrivacyRecordStore(container: fixture.localStore.container),
            privateContentPurger: MetadataTestPrivateContentPurger(),
            entityIndex: FakeSpotlightIndex(),
            retryStore: UserDefaultsLocalPrivacyPurgeRetryStore(defaults: defaults), automaticallyRetry: false
        )
        #expect(await purge.purge(ownerUserID: fixture.owner, scope: .departingUser) == .completed)
        await #expect(throws: LocalPrivacyWriteGuard.WriteError.self) {
            try await fixture.pending.enqueue(PendingSyncOperationRequest(
                ownerUserID: fixture.owner, operation: fixture.operations.makeOperation(),
                operationKind: .updateMediaAlternative, idempotencyScope: fixture.target.scope,
                requestData: try JSONEncoder().encode(fixture.edit("Must stay removed")), privacyToken: token
            ))
        }
        #expect(try await fixture.pending.inFlightOperations(
            ownerUserID: fixture.owner, kind: .updateMediaAlternative
        ).isEmpty)
        // Opt-in protection leaves the semantics of unrelated outbox operations intact.
        try await fixture.pending.enqueue(PendingSyncOperationRequest(
            ownerUserID: fixture.owner, operation: fixture.operations.makeOperation(),
            operationKind: .createMemory, idempotencyScope: "unrelated"
        ))
        #expect(try await fixture.pending.inFlightOperations(
            ownerUserID: fixture.owner, kind: .createMemory
        ).count == 1)
    }

    @Test func acceptedCorrectionStaysVisibleWhenAnImmutableHistorySourceHasNotRefreshed() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        let target = MediaAlternativeTarget.drawAndGuess(roundID: UUID())
        var context = ThreadChatContext(coupleID: fixture.couple)
        context.participants.currentUserID = fixture.owner
        context.operationProvider = fixture.operations
        let model = MediaAlternativeEditorModel(target: target, context: context, service: fixture.service)
        await model.prepare()
        model.open(currentText: "The original history snapshot")
        model.text = "An authored correction"
        await model.save()
        let pending = try #require(try await fixture.pending.inFlightOperations(
            ownerUserID: fixture.owner, kind: .updateMediaAlternative
        ).first)
        let accepted = MediaAlternativeEdit(coupleID: fixture.couple, target: target,
                                            text: "The server's accepted text")
        try await fixture.caches.apply(accepted, ownerUserID: fixture.owner, operation: pending.operation,
                                   stamp: await fixture.caches.stamp(ownerUserID: fixture.owner))
        try await fixture.pending.markSucceeded(clientOperationID: pending.operation.id, at: Date())
        await model.reloadPending()
        #expect(model.pending == nil)
        #expect(model.acceptedText == accepted.text)
        model.sourceChanged()
        #expect(model.acceptedText == nil)
    }

}

private actor HoldingMediaAlternativeGateway {
    private var started = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Void, Never>?

    func update(_ edit: MediaAlternativeEdit, operation _: SyncClientOperation) async -> MediaAlternativeAcceptedText {
        await withCheckedContinuation { continuation in
            completion = continuation
            started = true
            requestWaiters.forEach { $0.resume() }
            requestWaiters = []
        }
        return MediaAlternativeAcceptedText(accessibilityText: edit.text)
    }
    func waitForRequest() async {
        if started { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }
    func release() { completion?.resume(); completion = nil }
}
extension HoldingMediaAlternativeGateway: MediaAlternativeGateway {}

private struct MetadataTestPrivateContentPurger: LocalPrivateContentPurging {
    // swiftlint:disable:next async_without_await
    func purge(ownerUserID _: UUID, scope _: LocalPrivacyPurgeScope) async {}
}

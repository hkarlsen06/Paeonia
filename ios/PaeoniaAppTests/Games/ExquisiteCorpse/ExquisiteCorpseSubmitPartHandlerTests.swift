import Foundation
import Testing
@testable import PaeoniaApp

/// How a queued part reaches the server: what it uploads, which ids it sends, what a
/// refusal does, and that nothing the person drew is lost.
@MainActor
struct ExquisiteCorpseSubmitPartHandlerTests {
    private typealias Fixture = ExquisiteCorpseFixture
    private typealias Submitted = ScriptedExquisiteCorpseGateway.SubmittedPart

    private let environment = ExquisiteCorpseDataEnvironment()
    private let drawingBytes = Data([1, 1, 1])
    private let stripBytes = Data([2, 2])

    private func send(
        _ payload: ExquisiteCorpseSubmitPartPayload,
        operation: SyncClientOperation = SyncClientOperation(clientID: UUID(), clientSequence: 1)
    ) async throws -> PendingSyncOperationSendResult {
        try await environment.submitHandler().send(
            try corpseSnapshot(.exquisiteCorpseSubmitPart, payload, operation: operation),
            context: environment.context()
        )
    }

    private func draft(of payload: ExquisiteCorpseSubmitPartPayload) -> Data? {
        environment.drawingStore.draft(ownerUserID: Fixture.me, roundID: payload.partID)
    }

    // MARK: Sending

    @Test func aHeadUploadsTheDrawingThenTheStripAndSubmitsBoth() async throws {
        let idea = Fixture.idea("a grandma")
        let head = Fixture.distinctPart(partIndex: 0, idea: idea)
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 7)

        let result = try await send(head, operation: operation)

        #expect(result == .succeeded)
        let uploads = environment.transfer.uploads
        let strip = try #require(head.strip)
        #expect(uploads.map(\.data) == [drawingBytes, stripBytes])
        #expect(uploads.map(\.parent.purpose) == ["exquisite_corpse_drawing", "exquisite_corpse_strip"])
        #expect(uploads.map(\.parent.kind) == ["exquisite_corpse_part", "exquisite_corpse_part"])
        #expect(uploads.map(\.parent.id) == [head.partID, head.partID])
        #expect(uploads.map(\.parent.gameID) == [head.gameID, head.gameID])
        #expect(uploads.map(\.coupleID) == [Fixture.couple, Fixture.couple])
        // Each upload replays its own stored operations.
        #expect(uploads.map(\.reserveOperation) == [head.drawing.reserveOperation, strip.reserveOperation])
        #expect(uploads.map(\.finalizeOperation) == [head.drawing.finalizeOperation, strip.finalizeOperation])
        #expect(environment.gateway.submitted == [
            Submitted(
                partID: head.partID,
                figureID: head.figureID,
                partIndex: 0,
                drawingAssetID: Fixture.drawingAssetID,
                stripAssetID: Fixture.stripAssetID,
                ideaID: idea.id,
                operationID: operation.id
            ),
        ])
    }

    @Test func theLegsHaveNoStrip() async throws {
        let legs = Fixture.distinctPart(partIndex: 2)

        let result = try await send(legs)

        #expect(result == .succeeded)
        #expect(environment.transfer.uploads.map(\.parent.purpose) == ["exquisite_corpse_drawing"])
        #expect(environment.gateway.submitted.map(\.stripAssetID) == [nil])
        #expect(environment.gateway.submitted.map(\.ideaID) == [nil])
    }

    @Test func theDrawingIsKeptAsTheServersCopySoTheRevealNeverDownloadsIt() async throws {
        let head = Fixture.distinctPart()

        _ = try await send(head)

        let store = environment.drawingStore
        #expect(store.downloadedDrawing(mediaAssetID: Fixture.drawingAssetID) == drawingBytes)
        // Nobody needs the drawer's own strip.
        #expect(store.downloadedDrawing(mediaAssetID: Fixture.stripAssetID) == nil)
    }

    @Test func theServersStateIsReadBeforeThePartLeavesTheQueue() async throws {
        let head = Fixture.distinctPart()

        let result = try await send(head)

        #expect(result == .succeeded)
        #expect(environment.gateway.calls == ["submit", "load"])
        #expect(await environment.cache.document(ownerUserID: Fixture.me).state == Fixture.state(version: 2))
    }

    @Test func aPartStaysQueuedWhenTheStateReadAfterItFails() async throws {
        environment.gateway.setStateToLoad(nil)
        let head = Fixture.distinctPart()
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 3)

        let result = try await send(head, operation: operation)

        guard case let .retry(after: retryDate) = result, let date = retryDate else {
            Issue.record("Expected a retry with a date, got \(result)")
            return
        }
        // Soon, not after the usual minute.
        #expect(date.timeIntervalSinceNow < 5)
        // The next try replays the same operation, and the server answers it from its record.
        environment.gateway.setStateToLoad(Fixture.state(version: 2))
        let again = try await send(head, operation: operation)
        #expect(again == .succeeded)
        #expect(environment.gateway.submitted.map(\.operationID) == [operation.id, operation.id])
    }

    @Test func aPartAnotherSendAlreadyTookComesBackAsADraft() async throws {
        // A retry of this send gets the server's stored answer. A duplicate means another
        // send, such as this person's other phone, took the part, and this drawing never went out.
        environment.gateway.setSubmitError(Fixture.refusal("23505", "duplicate key"))
        let head = Fixture.distinctPart()

        let result = try await send(head)

        expectCorpseTerminalFailure(result)
        #expect(draft(of: head) == drawingBytes)
        #expect(await environment.cache.takeNotices(ownerUserID: Fixture.me) == [.partRejected])
    }

    @Test func aPayloadThatCannotBeReadIsDropped() async throws {
        let result = try await environment.submitHandler().send(
            try corpseSnapshot(.exquisiteCorpseSubmitPart, "not a part"),
            context: environment.context()
        )

        expectCorpseTerminalFailure(result)
        #expect(environment.gateway.calls.isEmpty)
    }

    // MARK: Refusals

    @Test(arguments: [
        ("42501", "it is not your turn"),
        ("23514", "this part is out of date"),
        ("23514", "this figure is out of date"),
        ("23514", "exquisite corpse upload contract is invalid"),
    ])
    func aRefusalARetryCannotFixPutsTheDrawingBackAndTellsThePerson(code: String, message: String) async throws {
        environment.gateway.setSubmitError(Fixture.refusal(code, message))
        let head = Fixture.distinctPart(idea: Fixture.idea("a grandma"))
        await environment.cache.saveIdea("idea-a-grandma", partID: head.partID, ownerUserID: Fixture.me)

        let result = try await send(head)

        expectCorpseTerminalFailure(result)
        #expect(draft(of: head) == drawingBytes)
        #expect(await environment.cache.takeNotices(ownerUserID: Fixture.me) == [.partRejected])
        // The idea stays, so the restored canvas shows the same chip.
        #expect(await environment.cache.document(ownerUserID: Fixture.me).ideas[head.partID] == "idea-a-grandma")
        #expect(environment.gateway.calls == ["submit"])
    }

    @Test func anIdeaTheServerDoesNotKnowIsForgottenSoThePartCanBeSentWithout() async throws {
        environment.gateway.setSubmitError(Fixture.refusal("22023", "the idea is not on the list for this part"))
        let head = Fixture.distinctPart(idea: Fixture.idea("a grandma"))
        await environment.cache.saveIdea("idea-a-grandma", partID: head.partID, ownerUserID: Fixture.me)

        let result = try await send(head)

        expectCorpseTerminalFailure(result)
        #expect(draft(of: head) == drawingBytes)
        #expect(await environment.cache.takeNotices(ownerUserID: Fixture.me) == [.partRejected])
        #expect(await environment.cache.document(ownerUserID: Fixture.me).ideas[head.partID] == nil)
    }

    @Test func aWrongArgumentThatIsNotTheIdeaKeepsTheIdea() async throws {
        environment.gateway.setSubmitError(Fixture.refusal("22023", "the legs take no strip"))
        let head = Fixture.distinctPart()
        await environment.cache.saveIdea("idea-a-grandma", partID: head.partID, ownerUserID: Fixture.me)

        let result = try await send(head)

        expectCorpseTerminalFailure(result)
        #expect(await environment.cache.document(ownerUserID: Fixture.me).ideas[head.partID] == "idea-a-grandma")
    }

    @Test func noConnectionKeepsRetryingWithoutCounting() async throws {
        environment.gateway.setSubmitError(URLError(.notConnectedToInternet))
        let head = Fixture.distinctPart()
        let handler = environment.submitHandler()
        let snapshot = try corpseSnapshot(.exquisiteCorpseSubmitPart, head)

        for _ in 0..<5 {
            let error = await corpseThrownError { try await handler.send(snapshot, context: environment.context()) }
            #expect(error is URLError)
        }

        let document = await environment.cache.document(ownerUserID: Fixture.me)
        #expect(document.unexplainedRefusals.isEmpty)
        #expect(document.notices.isEmpty)
        #expect(draft(of: head) == nil)
    }

    @Test func anUploadThatFailsOfflineStopsBeforeTheSubmit() async throws {
        environment.transfer.setUploadError(URLError(.notConnectedToInternet))
        let head = Fixture.distinctPart()

        let error = await corpseThrownError { try await send(head) }

        #expect(error is URLError)

        #expect(environment.gateway.calls.isEmpty)
        #expect(draft(of: head) == nil)
    }

    @Test func aRefusalWeCannotExplainDropsThePartOnTheThirdTry() async throws {
        environment.gateway.setSubmitError(Fixture.refusal("XX000", "something we do not know"))
        let head = Fixture.distinctPart()
        let handler = environment.submitHandler()
        let snapshot = try corpseSnapshot(.exquisiteCorpseSubmitPart, head)

        for _ in 0..<2 {
            let error = await corpseThrownError { try await handler.send(snapshot, context: environment.context()) }
            #expect(error is PaeoniaConvexError)
        }
        #expect(draft(of: head) == nil)
        #expect(await environment.cache.takeNotices(ownerUserID: Fixture.me).isEmpty)

        let third = try await handler.send(snapshot, context: environment.context())

        expectCorpseTerminalFailure(third)
        #expect(draft(of: head) == drawingBytes)
        #expect(await environment.cache.takeNotices(ownerUserID: Fixture.me) == [.partRejected])
    }
}

/// Uploads the server deleted before the part was sent.
extension ExquisiteCorpseSubmitPartHandlerTests {
    // MARK: Uploads the server deleted

    @Test(arguments: [
        ("23514", "exquisite corpse drawing asset is not usable"),
        ("23514", "exquisite corpse strip asset is not usable"),
        ("42501", "media upload reservation is not available"),
        // The reservation ran out while the bytes were uploading.
        ("22023", "media upload reservation is expired"),
    ])
    func aDeletedUploadIsQueuedAgainWithNewOperations(code: String, message: String) async throws {
        environment.gateway.setSubmitError(Fixture.refusal(code, message))
        let head = Fixture.distinctPart(idea: Fixture.idea("a grandma"))
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 4)
        try await environment.enqueue(.exquisiteCorpseSubmitPart, head, operation: operation)

        let result = try await send(head, operation: operation)

        expectCorpseTerminalFailure(result)
        let queued = await environment.queued(.exquisiteCorpseSubmitPart).filter { $0.operation.id != operation.id }
        let replacement = try #require(queued.first)
        let renewed = try #require(
            replacement.requestData.flatMap {
                try? JSONDecoder().decode(ExquisiteCorpseSubmitPartPayload.self, from: $0)
            }
        )
        #expect(queued.count == 1)
        // The same place in the order, and the same part.
        #expect(replacement.operation.clientID == operation.clientID)
        #expect(replacement.operation.clientSequence == operation.clientSequence)
        #expect(replacement.operation.localCreatedAt == operation.localCreatedAt)
        #expect(renewed.partID == head.partID)
        #expect(renewed.idea == head.idea)
        #expect(renewed.renewedAt != nil)
        // The kept drawings upload again with operations the server has not seen.
        let strip = try #require(head.strip)
        let renewedStrip = try #require(renewed.strip)
        #expect(renewed.drawing.data == drawingBytes)
        #expect(renewedStrip.data == stripBytes)
        #expect(renewed.drawing.reserveOperation.id != head.drawing.reserveOperation.id)
        #expect(renewed.drawing.finalizeOperation.id != head.drawing.finalizeOperation.id)
        #expect(renewedStrip.reserveOperation.id != strip.reserveOperation.id)
        #expect(renewedStrip.finalizeOperation.id != strip.finalizeOperation.id)
        #expect(renewed.drawing.reserveOperation.clientSequence == head.drawing.reserveOperation.clientSequence)
        // Nothing went back to the canvas, because the part is still on its way.
        #expect(draft(of: head) == nil)
        #expect(await environment.cache.takeNotices(ownerUserID: Fixture.me).isEmpty)
    }

    @Test func anUploadThatIsGoneAgainSoonAfterARenewalIsNotRenewedAgain() async throws {
        environment.gateway.setSubmitError(Fixture.refusal("23514", "exquisite corpse drawing asset is not usable"))
        let head = Fixture.distinctPart(renewedAt: Date())
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 4)
        try await environment.enqueue(.exquisiteCorpseSubmitPart, head, operation: operation)

        let result = try await send(head, operation: operation)

        expectCorpseTerminalFailure(result)
        #expect(await environment.queued(.exquisiteCorpseSubmitPart).map(\.operation.id) == [operation.id])
        #expect(draft(of: head) == drawingBytes)
        #expect(await environment.cache.takeNotices(ownerUserID: Fixture.me) == [.partRejected])
    }

    @Test func anOldRenewalDoesNotStopTheNextOne() async throws {
        environment.gateway.setSubmitError(Fixture.refusal("23514", "exquisite corpse drawing asset is not usable"))
        let head = Fixture.distinctPart(renewedAt: Date().addingTimeInterval(-2 * 24 * 60 * 60))
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 4)
        try await environment.enqueue(.exquisiteCorpseSubmitPart, head, operation: operation)

        let result = try await send(head, operation: operation)

        expectCorpseTerminalFailure(result)
        #expect(await environment.queued(.exquisiteCorpseSubmitPart).count == 2)
        #expect(draft(of: head) == nil)
    }
}

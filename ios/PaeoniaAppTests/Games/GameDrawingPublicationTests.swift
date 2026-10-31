import Foundation
import Testing
@testable import PaeoniaApp

nonisolated enum GameDraftChange: CaseIterable, Equatable, Sendable {
    case matching, drawing, description, backgroundSave
}

@MainActor
struct GameDrawingPublicationTests {
    @Test(arguments: GameDraftChange.allCases, [false, true])
    func acceptedResponseClearsOnlyItsOwnPublishedDraft(change: GameDraftChange, usesFiles: Bool) async throws {
        let state = GameFixture.state(settings: GameFixture.settings(),
            game: GameFixture.game(state: .guessing, turn: GameFixture.partner),
            round: GameFixture.round(state: .guessing, drawer: GameFixture.me, hasDrawing: true))
        let environment = GamesTestEnvironment(state: state)
        environment.gateway.setStateToLoad(state)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store: any GameDrawingStoring
        if usesFiles { store = FileGameDrawingStore(directoryURL: directory) } else { store = environment.drawingStore }
        let owner = GameFixture.me
        let couple = try #require(GameFixture.participants.coupleID)
        let round = GameFixture.roundID
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: owner)
        let published = Data([1, 2, 3]), newer = Data([4, 5, 6])
        store.saveDraft(published, ownerUserID: owner, roundID: round)
        try store.saveDraftDescription("The published description", ownerUserID: owner, coupleID: couple,
                                        roundID: round, privacyToken: token)
        let payload = GameSubmitDrawingPayload(gameID: GameFixture.gameID, roundID: round, coupleID: couple,
            drawingData: published, drawingAccessibilityText: "The published description",
            draftPublicationID: try store.markDraftForPublication(ownerUserID: owner, roundID: round),
            reserveOperation: SyncClientOperation(clientID: UUID(), clientSequence: 1),
            finalizeOperation: SyncClientOperation(clientID: UUID(), clientSequence: 2))
        var backgroundTicket: Int?
        switch change {
        case .matching: break
        case .drawing: store.saveDraft(newer, ownerUserID: owner, roundID: round)
        case .description:
            try store.saveDraftDescription("A newer description", ownerUserID: owner, coupleID: couple,
                                            roundID: round, privacyToken: token)
        case .backgroundSave: backgroundTicket = store.beginDraftSave(ownerUserID: owner, roundID: round)
        }
        let acceptedStore: any GameDrawingStoring = usesFiles && change != .backgroundSave
            ? FileGameDrawingStore(directoryURL: directory) : store
        let handler = SubmitGameDrawingPendingOperationHandler(gateway: environment.gateway,
            transfer: environment.transfer, cache: environment.cache, drawingStore: acceptedStore)
        let result = try await handler.send(try snapshot(.submitGameDrawing, payload),
                                            context: syncContext(environment.pending))
        #expect(result == .succeeded)
        if let backgroundTicket { store.saveDraft(newer, ownerUserID: owner, roundID: round, ticket: backgroundTicket) }
        if change == .matching {
            #expect(store.draft(ownerUserID: owner, roundID: round) == nil)
            #expect(try store.draftDescription(ownerUserID: owner, coupleID: couple, roundID: round) == nil)
        } else {
            #expect(store.draft(ownerUserID: owner, roundID: round) == (change == .description ? published : newer))
            #expect(try store.draftDescription(ownerUserID: owner, coupleID: couple, roundID: round)
                == (change == .description ? "A newer description" : "The published description"))
        }
    }
    @Test(arguments: GameDraftChange.allCases, [false, true])
    func acceptedCreaturePartClearsOnlyItsOwnPublishedDraft(change: GameDraftChange, usesFiles: Bool) async throws {
        let environment = ExquisiteCorpseDataEnvironment()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store: any GameDrawingStoring = usesFiles
            ? FileGameDrawingStore(directoryURL: directory) : environment.drawingStore
        let owner = ExquisiteCorpseFixture.me
        let couple = ExquisiteCorpseFixture.couple
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: owner)
        let original = ExquisiteCorpseFixture.distinctPart()
        let part = original.partID
        let published = original.drawing.data, newer = Data([4, 5, 6])
        store.saveDraft(published, ownerUserID: owner, roundID: part)
        try store.saveDraftDescription("The published description", ownerUserID: owner, coupleID: couple,
                                       roundID: part, privacyToken: token)
        let payload = ExquisiteCorpseSubmitPartPayload(gameID: original.gameID, figureID: original.figureID,
            partID: part, partIndex: original.partIndex, coupleID: couple,
            drawing: ExquisiteCorpseQueuedUpload(data: published, accessibilityText: "The published description",
                reserveOperation: original.drawing.reserveOperation,
                finalizeOperation: original.drawing.finalizeOperation),
            strip: original.strip, idea: original.idea, createdAt: original.createdAt,
            draftPublicationID: try store.markDraftForPublication(ownerUserID: owner, roundID: part))
        var backgroundTicket: Int?
        switch change {
        case .matching: break
        case .drawing: store.saveDraft(newer, ownerUserID: owner, roundID: part)
        case .description:
            try store.saveDraftDescription("A newer description", ownerUserID: owner, coupleID: couple,
                                           roundID: part, privacyToken: token)
        case .backgroundSave: backgroundTicket = store.beginDraftSave(ownerUserID: owner, roundID: part)
        }
        #expect(payload.withNewUploads(renewedAt: Date()).draftPublicationID == payload.draftPublicationID)
        let reopened: any GameDrawingStoring = usesFiles && change != .backgroundSave
            ? FileGameDrawingStore(directoryURL: directory) : store
        let handler = ExquisiteCorpseSubmitPartHandler(gateway: environment.gateway,
            transfer: environment.transfer, cache: environment.cache, drawingStore: reopened)
        let result = try await handler.send(
            try corpseSnapshot(.exquisiteCorpseSubmitPart, payload), context: environment.context())
        #expect(result == .succeeded)
        if let backgroundTicket { store.saveDraft(newer, ownerUserID: owner, roundID: part, ticket: backgroundTicket) }
        if change == .matching {
            #expect(store.draft(ownerUserID: owner, roundID: part) == nil)
            #expect(try store.draftDescription(ownerUserID: owner, coupleID: couple, roundID: part) == nil)
        } else {
            #expect(store.draft(ownerUserID: owner, roundID: part) == (change == .description ? published : newer))
            #expect(try store.draftDescription(ownerUserID: owner, coupleID: couple, roundID: part)
                == (change == .description ? "A newer description" : "The published description"))
        }
    }

}

import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

@MainActor
struct GameDrawingDescriptionTests {
    @Test
    func fileDraftKeepsTextAcrossRelaunchAndSeparatesOwnerAndCouple() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID(), couple = UUID(), round = UUID()
        let store = FileGameDrawingStore(directoryURL: directory)
        let model = GameDrawingDescriptionDraftModel()
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: owner)
        model.configure(store: store, owner: owner, couple: couple, round: round, privacyToken: token)
        model.update("A round face with three eyes and a wide smile.")
        let relaunched = GameDrawingDescriptionDraftModel()
        relaunched.configure(store: FileGameDrawingStore(directoryURL: directory), owner: owner,
                             couple: couple, round: round, privacyToken: token)
        #expect(relaunched.text == model.text)
        #expect(try store.draftDescription(ownerUserID: UUID(), coupleID: couple, roundID: round) == nil)
        #expect(try store.draftDescription(ownerUserID: owner, coupleID: UUID(), roundID: round) == nil)
        store.clearDownloads()
        #expect(try store.draftDescription(ownerUserID: owner, coupleID: couple, roundID: round) == model.text)
        LocalPrivacyWriteGuard.shared.invalidate(ownerUserID: owner)
        store.clearAll()
        model.update("A late edit from the dismissed authoring sheet.")
        #expect(model.saveFailed)
        #expect(!model.canSend)
        #expect(try store.draftDescription(ownerUserID: owner, coupleID: couple, roundID: round) == nil)
    }

    @Test
    func failedDiskSaveRetainsTypedTextAndCanRecover() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = UUID(), couple = UUID(), round = UUID()
        let model = GameDrawingDescriptionDraftModel()
        model.configure(store: FileGameDrawingStore(directoryURL: directory), owner: owner, couple: couple,
                        round: round, privacyToken: LocalPrivacyWriteGuard.shared.token(ownerUserID: owner))
        // A file where the store needs its folder forces the real filesystem failure.
        try Data([0]).write(to: directory)
        model.update("Two boots below a blue coat.")
        #expect(model.saveFailed)
        #expect(model.text == "Two boots below a blue coat.")
        try FileManager.default.removeItem(at: directory)
        model.save()
        #expect(!model.saveFailed)
        #expect(try FileGameDrawingStore(directoryURL: directory).draftDescription(
            ownerUserID: owner, coupleID: couple, roundID: round) == model.text)
    }

    @Test
    func drawingGamesRestoreAuthoredTextThroughTheirRealViewModels() async {
        let drawEnvironment = GamesTestEnvironment(state: GameFixture.state(
            settings: GameFixture.settings(), game: GameFixture.game(state: .drawing, turn: GameFixture.partner),
            round: GameFixture.round(state: .drawing, drawer: GameFixture.me)))
        let first = DrawAndGuessViewModel(dependencies: drawEnvironment.dependencies(),
                                         participants: GameFixture.participants)
        await first.reload()
        first.drawingDescription.update("A tall outline with four legs.")
        let second = DrawAndGuessViewModel(dependencies: drawEnvironment.dependencies(),
                                          participants: GameFixture.participants)
        await second.reload()
        #expect(second.drawingDescription.text == "A tall outline with four legs.")

        let creatureEnvironment = ExquisiteCorpseTestEnvironment(state: ExquisiteCorpseFixture.myBodyTurn())
        let body = ExquisiteCorpseViewModel(dependencies: creatureEnvironment.dependencies(withRoom: false),
                                          participants: ExquisiteCorpseTestEnvironment.participants)
        await body.reload()
        body.drawingDescription.update("A coat with three pockets.")
        let restored = ExquisiteCorpseViewModel(dependencies: creatureEnvironment.dependencies(withRoom: false),
                                              participants: ExquisiteCorpseTestEnvironment.participants)
        await restored.reload()
        #expect(restored.drawingDescription.text == "A coat with three pockets.")
    }

    @Test
    func queuedCreatureCorrectionCannotPopulateAnUnfinishedPartProjection() async throws {
        let cache = InMemoryExquisiteCorpseCache()
        let state = ExquisiteCorpseFixture.partnerBodyTurn()
        let head = try #require(state.currentFigure?.parts.first)
        let owner = ExquisiteCorpseFixture.me
        await cache.saveState(state, ownerUserID: owner)
        let edit = MediaAlternativeEdit(coupleID: state.coupleID, target: .exquisiteCorpse(partID: head.id),
                                         text: "The hidden head has four eyes.")
        await cache.updateDrawingDescription(edit, ownerUserID: owner,
            privacyToken: LocalPrivacyWriteGuard.shared.token(ownerUserID: owner))
        let kept = await cache.document(ownerUserID: owner)
        #expect(kept.state?.currentFigure?.parts.first?.drawingAccessibilityText == nil)
    }

    @Test(arguments: [false, true])
    func liveSolveRetainsAnInvalidDescriptionAndTheDrawingUntilTheAuthorRetries(unreadable: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileGameDrawingStore(directoryURL: directory)
        let drawing = GameFixture.umbrella()
        store.saveDraft(drawing.dataRepresentation(), ownerUserID: GameFixture.me, roundID: GameFixture.roundID)
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: GameFixture.me)
        let coupleID = try #require(GameFixture.participants.coupleID)
        let originalText = unreadable ? "A curved top above a straight handle." : String(repeating: "x", count: 10_001)
        try store.saveDraftDescription(originalText, ownerUserID: GameFixture.me, coupleID: coupleID,
                                        roundID: GameFixture.roundID, privacyToken: token)
        if unreadable {
            let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            let descriptionFile = try #require(
                files.allObjects.compactMap { $0 as? URL }.first { $0.pathExtension == "json" }
            )
            try Data([0]).write(to: descriptionFile)
        }
        let state = GameFixture.state(settings: GameFixture.settings(),
            game: GameFixture.game(state: .choosingWord, turn: GameFixture.partner, roundID: nil),
            round: GameFixture.round(state: .solved, drawer: GameFixture.me))
        let environment = GamesTestEnvironment(state: state)
        var dependencies = environment.dependencies()
        dependencies.drawingStore = store
        let model = DrawAndGuessViewModel(dependencies: dependencies, participants: GameFixture.participants)
        await model.reload()
        for _ in 0..<200 where !model.drawingAwaitingRetry { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.drawingAwaitingRetry)
        #expect(await environment.queued(.submitGameDrawing).isEmpty)
        #expect(store.draft(ownerUserID: GameFixture.me, roundID: GameFixture.roundID) != nil)
        let corrected = "A curved top above a straight handle."
        if unreadable {
            try store.saveDraftDescription(corrected, ownerUserID: GameFixture.me, coupleID: coupleID,
                                            roundID: GameFixture.roundID, privacyToken: token)
            model.drawingDescription.load()
        } else {
            model.drawingDescription.update(corrected)
        }
        model.retryFinishedDrawing()
        for _ in 0..<200 {
            if !model.board.isFinishing, !(await environment.queued(.submitGameDrawing)).isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let bytes = try #require(await environment.queued(.submitGameDrawing).first?.requestData)
        let payload = try JSONDecoder().decode(GameSubmitDrawingPayload.self, from: bytes)
        #expect(payload.drawingAccessibilityText == corrected)
        #expect(try PKDrawing(data: payload.drawingData).paeoniaContentSignature == drawing.paeoniaContentSignature)
    }
}

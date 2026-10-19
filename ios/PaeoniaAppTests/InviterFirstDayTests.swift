import Foundation
import Testing
@testable import PaeoniaApp

struct FirstDayRequestTests {
    private let operation = SyncClientOperation(
        id: firstDayUUID(21),
        clientID: firstDayUUID(22),
        clientSequence: 4,
        localCreatedAt: Date(timeIntervalSince1970: 40)
    )

    private func json(_ request: some Encodable) throws -> [String: Any] {
        let data = try PaeoniaConvexClient.encoder.encode(request)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func startDateClearsWithAnExplicitNullAndCarriesTheOperation() throws {
        let body = try json(SetFirstDayStartedOnRequest(startedOn: nil, operation: operation))

        #expect(body["p_started_on"] is NSNull)
        #expect(body["p_client_operation_id"] as? String == operation.id.uuidString)
        #expect(body["p_client_id"] as? String == operation.clientID.uuidString)
        #expect(body["p_client_sequence"] as? Int == 4)
        #expect(body["p_local_created_at"] is String)
    }

    @Test func draftDecodesAndPicksThePromptForTheLanguage() throws {
        let json = """
        {
          "started_on": null,
          "questions": [
            { "slot_number": 1, "question_version_id": "\(firstDayUUID(1).uuidString.lowercased())",
              "question_key": "a", "prompt_en": "English", "prompt_nb": "Norsk",
              "short_prompt_en": "E", "short_prompt_nb": "N", "answer_text": "Yes",
              "answered_at": "2026-10-17T10:00:00.000Z" },
            { "slot_number": 2, "question_version_id": "\(firstDayUUID(2).uuidString.lowercased())",
              "question_key": "b", "prompt_en": "Two", "prompt_nb": "To",
              "short_prompt_en": "T", "short_prompt_nb": "T", "answer_text": null, "answered_at": null }
          ],
          "drawing": {
            "media_asset_id": "\(firstDayUUID(7).uuidString)",
            "revision_id": "\(firstDayUUID(8).uuidString)",
            "saved_at": "2026-10-17T10:00:00.000Z"
          },
          "updated_at": "2026-10-17T10:00:00.000Z"
        }
        """
        let draft = try PaeoniaConvexClient.decoder.decode(FirstDayDraft.self, from: Data(json.utf8))

        #expect(draft.answeredCount == 1)
        #expect(!draft.hasAnsweredAll)
        #expect(draft.questions.first?.questionVersionID == firstDayUUID(1))
        #expect(draft.drawing?.mediaAssetID == firstDayUUID(7))
        #expect(draft.questions.first?.prompt(for: Locale(identifier: "nb_NO")) == "Norsk")
        #expect(draft.questions.first?.prompt(for: Locale(identifier: "en_US")) == "English")
    }
}

@MainActor
struct FirstDayQuestionsModelTests {
    private func makeModel(
        answered: Int,
        gateway: FirstDayGatewaySpy? = nil,
        questionTimeEnabled: Bool = false
    ) throws -> (FirstDayQuestionsModel, FirstDayGatewaySpy) {
        let gateway = gateway ?? FirstDayGatewaySpy()
        let model = FirstDayQuestionsModel(
            questions: firstDayDraft(answered: answered).questions,
            ownerUserID: firstDayUUID(100),
            gateway: gateway,
            operationProvider: FixedDailyChallengeOperationProvider(),
            draftStore: UserDefaultsFirstDayAnswerDraftStore(defaults: try firstDayTestDefaults()),
            preferences: FirstDayPreferencesFake(questionTimeEnabled: questionTimeEnabled)
        )
        return (model, gateway)
    }

    @Test func savesEachAnswerTrimmedAndMovesOnToQuestionTime() async throws {
        let (model, gateway) = try makeModel(answered: 0)

        model.text = "  First  "
        #expect(await model.continueFromQuestion())
        model.text = "Second"
        #expect(await model.continueFromQuestion())

        let saved = await gateway.savedAnswers
        #expect(saved.map(\.text) == ["First", "Second"])
        #expect(saved.map(\.questionVersionID) == [firstDayUUID(1), firstDayUUID(2)])
        #expect(model.answeredCount == 2)
        #expect(model.step == .questionTime)
    }

    @Test func aFailedSaveKeepsThePersonOnThePageWithTheirText() async throws {
        let gateway = FirstDayGatewaySpy()
        await gateway.fail("answer")
        let (model, _) = try makeModel(answered: 0, gateway: gateway)

        model.text = "Keep me"
        #expect(await model.continueFromQuestion() == false)

        #expect(model.step == .question(0))
        #expect(model.text == "Keep me")
        #expect(model.saveFailure == .offline)
        #expect(model.questions[0].answerText == nil)
    }

    @Test func typedTextSurvivesReopening() throws {
        let defaults = try firstDayTestDefaults()
        let store = UserDefaultsFirstDayAnswerDraftStore(defaults: defaults)
        let questions = firstDayDraft(answered: 0).questions
        let first = FirstDayQuestionsModel(
            questions: questions,
            ownerUserID: firstDayUUID(100),
            gateway: FirstDayGatewaySpy(),
            draftStore: store,
            preferences: nil
        )
        first.text = "Half written"

        let reopened = FirstDayQuestionsModel(
            questions: questions,
            ownerUserID: firstDayUUID(100),
            gateway: FirstDayGatewaySpy(),
            draftStore: store,
            preferences: nil
        )

        #expect(reopened.text == "Half written")
    }
}

struct FirstDayStartedOnTests {
    private let owner = firstDayUUID(100)

    private func snapshot(startedOn: String) throws -> PendingSyncOperationSnapshot {
        PendingSyncOperationSnapshot(
            ownerUserID: owner,
            operation: SyncClientOperation(clientID: firstDayUUID(22), clientSequence: 1),
            operationKind: .setFirstDayStartedOn,
            idempotencyScope: "first_day_draft:started_on",
            requestHash: nil,
            requestData: try JSONEncoder().encode(SetFirstDayStartedOnPayload(startedOn: startedOn)),
            status: .queued,
            attemptCount: 0,
            lastAttemptAt: nil,
            nextRetryAt: nil,
            lastError: nil,
            completedAt: nil
        )
    }

    private var context: SyncContext {
        SyncContext(
            session: SyncSession(userID: owner),
            reason: .localChange,
            stateStore: InMemorySyncStateRepository(),
            pendingOperationStore: InMemoryPendingSyncOperationRepository()
        )
    }

    @MainActor
    @Test func theDateIsQueuedOnThisPhone() async throws {
        let store = InMemoryPendingSyncOperationRepository()
        let queue = FirstDayStartedOnQueue(
            pendingOperationStore: store,
            operationProvider: FixedDailyChallengeOperationProvider()
        )

        try await queue.save(try PairingStartDate(rawValue: "2024-02-29"), ownerUserID: owner)

        let queued = try await store.inFlightOperations(ownerUserID: owner, kind: .setFirstDayStartedOn)
        let payload = try JSONDecoder().decode(
            SetFirstDayStartedOnPayload.self,
            from: try #require(queued.first?.requestData)
        )
        #expect(queued.count == 1)
        #expect(payload.startedOn == "2024-02-29")
    }

    @Test func onceThePersonIsPairedTheDateGoesToTheCouple() async throws {
        let gateway = FirstDayGatewaySpy()
        let dates = FirstDayRelationshipDatesSpy()
        await gateway.fail(
            "startedOn",
            with: PaeoniaConvexError.server(code: "23505", message: "user already has an active couple")
        )
        let handler = FirstDayStartedOnPendingOperationHandler(
            gateway: gateway,
            relationshipDates: dates,
            operationFactory: FirstDayOperationsFake()
        )

        let queued = try snapshot(startedOn: "2024-02-29")
        let result = try await handler.send(queued, context: context)

        #expect(result == .succeeded)
        #expect(await dates.savedStartedOn?.rawValue == "2024-02-29")
        #expect(await dates.savedOwnerUserID == owner)
        // The couple's write gets its own operation.
        let coupleOperation = try #require(await dates.savedOperation)
        #expect(coupleOperation.id != queued.operation.id)
    }

    @Test func aDateTheCoupleAlreadyHasIsNotReplaced() async throws {
        let gateway = FirstDayGatewaySpy()
        let dates = FirstDayRelationshipDatesSpy()
        await dates.seedExisting("2023-06-01")
        await gateway.fail(
            "startedOn",
            with: PaeoniaConvexError.server(code: "23505", message: "user already has an active couple")
        )
        let handler = FirstDayStartedOnPendingOperationHandler(
            gateway: gateway,
            relationshipDates: dates,
            operationFactory: FirstDayOperationsFake()
        )

        let result = try await handler.send(try snapshot(startedOn: "2024-02-29"), context: context)

        #expect(result == .succeeded)
        #expect(await dates.savedStartedOn == nil)
    }

    @Test func otherRefusalsStillEndTheDate() async throws {
        let gateway = FirstDayGatewaySpy()
        let dates = FirstDayRelationshipDatesSpy()
        await gateway.fail("startedOn", with: PaeoniaConvexError.server(code: "22007", message: "invalid date"))
        let handler = FirstDayStartedOnPendingOperationHandler(
            gateway: gateway,
            relationshipDates: dates,
            operationFactory: FirstDayOperationsFake()
        )

        let result = try await handler.send(try snapshot(startedOn: "2024-02-29"), context: context)

        let refusal = PaeoniaConvexError.server(code: "22007", message: "invalid date")
        #expect(result == .terminalFailure(refusal.description))
        #expect(await dates.savedStartedOn == nil)
    }

    @Test func theHandlerRetriesWhenOffline() async throws {
        let gateway = FirstDayGatewaySpy()
        let dates = FirstDayRelationshipDatesSpy()
        await gateway.fail("startedOn")
        let handler = FirstDayStartedOnPendingOperationHandler(
            gateway: gateway,
            relationshipDates: dates,
            operationFactory: FirstDayOperationsFake()
        )

        await #expect(throws: URLError.self) {
            _ = try await handler.send(try snapshot(startedOn: "2024-02-29"), context: context)
        }
    }
}

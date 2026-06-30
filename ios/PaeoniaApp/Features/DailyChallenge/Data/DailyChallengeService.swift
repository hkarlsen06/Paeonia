import Foundation
import Supabase

nonisolated struct DailyChallengeLoadResult: Equatable, Sendable {
    let snapshot: DailyChallengeSnapshot
    let streak: CoupleStreak
}

protocol DailyChallengeServicing: Actor {
    func loadToday(currentUserID: UUID) async throws -> DailyChallengeLoadResult
    func startToday(currentUserID: UUID, operation: SyncClientOperation) async throws -> DailyChallengeLoadResult
    /// Every daily question the current user has answered, across all days, as a flat
    /// chronological list. The caller groups it by day for the history overview.
    func loadHistory(currentUserID: UUID) async throws -> [DailyChallengeQuestion]
    func loadStreak() async throws -> CoupleStreak
    func editTextAnswer(instanceID: UUID, text: String, operation: SyncClientOperation) async throws -> UUID
    func editPartnerChoice(instanceID: UUID, selectedUserID: UUID, operation: SyncClientOperation) async throws -> UUID
    func shuffleQuestion(
        currentUserID: UUID,
        slotNumber: Int,
        operation: SyncClientOperation
    ) async throws -> DailyChallengeLoadResult
}

protocol SupabaseDailyChallengeGateway: Actor {
    func loadTodaySnapshot() async throws -> DailyChallengeRemoteSnapshotRow
    func startDailyChallenge(operation: SyncClientOperation) async throws -> DailyChallengeRemoteSnapshotRow
    func loadHistoryQuestions() async throws -> [DailyQuestionRow]
    func loadHistoryAnswerDetails() async throws -> [DailyAnswerDetailRow]
    func loadCoupleStreak() async throws -> CoupleStreak
    func loadAnswerDetails(coupleDayID: UUID) async throws -> [DailyAnswerDetailRow]
    func submitAnswer(instanceID: UUID, answerID: UUID, payload: DailyAnswerPayload, operation: SyncClientOperation) async throws -> UUID
    func editTextAnswer(instanceID: UUID, text: String, operation: SyncClientOperation) async throws -> UUID
    func editPartnerChoice(instanceID: UUID, selectedUserID: UUID, operation: SyncClientOperation) async throws -> UUID
    func shuffleQuestion(slotNumber: Int, operation: SyncClientOperation) async throws -> DailyChallengeRemoteSnapshotRow
}

actor SupabaseDailyChallengeService: DailyChallengeServicing {
    private let gateway: any SupabaseDailyChallengeGateway
    private let locale: Locale
    /// Injected so tests can supply an in-memory stand-in; the live path uses
    /// `FileDailyChallengeSnapshotCache.live()` by default. The cache is an
    /// implementation detail of the live service — it is not part of the
    /// `DailyChallengeServicing` protocol, which stays unchanged.
    private let cache: any DailyChallengeSnapshotCaching

    init(
        gateway: any SupabaseDailyChallengeGateway,
        locale: Locale = .current,
        cache: (any DailyChallengeSnapshotCaching)? = nil
    ) {
        self.gateway = gateway
        self.locale = locale
        self.cache = cache ?? FileDailyChallengeSnapshotCache.live()
    }

    static func live() throws -> SupabaseDailyChallengeService {
        let client = try PaeoniaSupabaseClientProvider.shared.client()
        return SupabaseDailyChallengeService(
            gateway: LiveSupabaseDailyChallengeGateway(client: client)
        )
    }

    func loadToday(currentUserID: UUID) async throws -> DailyChallengeLoadResult {
        let remote = try await gateway.loadTodaySnapshot()
        // Persist the raw row so the view model can seed itself on the next cold
        // launch before this network call returns.
        cache.save(remote, ownerUserID: currentUserID)
        return makeResult(currentUserID: currentUserID, remote: remote)
    }

    func startToday(
        currentUserID: UUID,
        operation: SyncClientOperation
    ) async throws -> DailyChallengeLoadResult {
        let remote = try await gateway.startDailyChallenge(operation: operation)
        cache.save(remote, ownerUserID: currentUserID)
        return makeResult(currentUserID: currentUserID, remote: remote)
    }

    /// Reads the couple's full answered-question history in two parallel calls — the
    /// question rows and the answer details — then merges them into domain questions
    /// the same way today's snapshot does. The backend only returns instances the
    /// viewer has answered, so every row carries the viewer's own answer.
    func loadHistory(currentUserID: UUID) async throws -> [DailyChallengeQuestion] {
        async let rowsTask = gateway.loadHistoryQuestions()
        async let detailsTask = gateway.loadHistoryAnswerDetails()
        let rows = try await rowsTask
        let answerDetails = try await detailsTask
        return DailyChallengeQuestion.list(
            currentUserID: currentUserID,
            rows: rows,
            answerDetails: answerDetails,
            locale: locale
        )
    }

    func loadStreak() async throws -> CoupleStreak {
        try await gateway.loadCoupleStreak()
    }

    func editTextAnswer(
        instanceID: UUID,
        text: String,
        operation: SyncClientOperation
    ) async throws -> UUID {
        do {
            return try await gateway.editTextAnswer(
                instanceID: instanceID,
                text: text,
                operation: operation
            )
        } catch {
            // Translate the "partner already answered" rejection into a typed error
            // so the UI can explain it plainly instead of inviting a pointless retry.
            if String(describing: error).contains("answers cannot be edited after your partner has answered") {
                throw DailyChallengeEditLockedError()
            }
            throw error
        }
    }

    func editPartnerChoice(
        instanceID: UUID,
        selectedUserID: UUID,
        operation: SyncClientOperation
    ) async throws -> UUID {
        do {
            return try await gateway.editPartnerChoice(
                instanceID: instanceID,
                selectedUserID: selectedUserID,
                operation: operation
            )
        } catch {
            // Same lock as text: once the partner has answered, the picks are revealed
            // and can no longer be changed. Surface it as a friendly, non-retry notice.
            if String(describing: error).contains("answers cannot be edited after your partner has answered") {
                throw DailyChallengeEditLockedError()
            }
            throw error
        }
    }

    func shuffleQuestion(
        currentUserID: UUID,
        slotNumber: Int,
        operation: SyncClientOperation
    ) async throws -> DailyChallengeLoadResult {
        let remote: DailyChallengeRemoteSnapshotRow
        do {
            remote = try await gateway.shuffleQuestion(slotNumber: slotNumber, operation: operation)
        } catch {
            // The backend caps each person at a few swaps per day. Translate that
            // one specific case into a typed error so the UI can show a friendly,
            // non-technical message instead of a generic failure.
            if String(describing: error).contains("daily shuffle limit reached") {
                throw DailyChallengeShuffleLimitError()
            }
            throw error
        }
        cache.save(remote, ownerUserID: currentUserID)
        return makeResult(currentUserID: currentUserID, remote: remote)
    }

    private func makeResult(
        currentUserID: UUID,
        remote: DailyChallengeRemoteSnapshotRow
    ) -> DailyChallengeLoadResult {
        // Delegates to the shared helper on the row itself so the row→domain
        // mapping is defined in exactly one place (DailyChallengeRemoteRows.swift).
        remote.loadResult(currentUserID: currentUserID, locale: locale)
    }
}

actor LiveSupabaseDailyChallengeGateway: SupabaseDailyChallengeGateway {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadTodaySnapshot() async throws -> DailyChallengeRemoteSnapshotRow {
        try await snapshotRPC("get_today_daily_challenge_snapshot")
    }

    func startDailyChallenge(operation: SyncClientOperation) async throws -> DailyChallengeRemoteSnapshotRow {
        try await snapshotRPC(
            "start_daily_challenge_snapshot",
            params: DailyChallengeClientOperationRequest(operation: operation)
        )
    }

    private func snapshotRPC(
        _ name: String
    ) async throws -> DailyChallengeRemoteSnapshotRow {
        let rows: [DailyChallengeRemoteSnapshotRow] = try await client
            .rpc(name)
            .execute()
            .value
        return rows.first ?? DailyChallengeRemoteSnapshotRow(
            questions: [],
            answerDetails: [],
            streak: nil,
            generatedAt: Date()
        )
    }

    private func snapshotRPC<Params: Encodable>(
        _ name: String,
        params: Params
    ) async throws -> DailyChallengeRemoteSnapshotRow {
        let rows: [DailyChallengeRemoteSnapshotRow] = try await client
            .rpc(
                name,
                params: params
            )
            .execute()
            .value
        return rows.first ?? DailyChallengeRemoteSnapshotRow(
            questions: [],
            answerDetails: [],
            streak: nil,
            generatedAt: Date()
        )
    }

    func loadHistoryQuestions() async throws -> [DailyQuestionRow] {
        try await client
            .rpc("get_daily_questions_history")
            .execute()
            .value
    }

    func loadHistoryAnswerDetails() async throws -> [DailyAnswerDetailRow] {
        try await client
            .rpc("get_daily_answer_history_details")
            .execute()
            .value
    }

    func loadCoupleStreak() async throws -> CoupleStreak {
        let rows: [CoupleStreakRow] = try await client
            .rpc("get_couple_streak")
            .execute()
            .value
        return rows.first?.streak ?? .none
    }

    func loadAnswerDetails(coupleDayID: UUID) async throws -> [DailyAnswerDetailRow] {
        try await client
            .rpc(
                "get_daily_answer_details",
                params: DailyAnswerDetailsRequest(coupleDayID: coupleDayID)
            )
            .execute()
            .value
    }

    func submitAnswer(
        instanceID: UUID,
        answerID: UUID,
        payload: DailyAnswerPayload,
        operation: SyncClientOperation
    ) async throws -> UUID {
        try await client
            .rpc(
                "submit_daily_answer",
                params: SubmitDailyAnswerRequest(
                    instanceID: instanceID,
                    answerID: answerID,
                    payload: payload,
                    operation: operation
                )
            )
            .execute()
            .value
    }

    func editTextAnswer(
        instanceID: UUID,
        text: String,
        operation: SyncClientOperation
    ) async throws -> UUID {
        try await client
            .rpc(
                "update_daily_answer_text",
                params: EditDailyTextAnswerRequest(
                    instanceID: instanceID,
                    text: text,
                    operation: operation
                )
            )
            .execute()
            .value
    }

    func editPartnerChoice(
        instanceID: UUID,
        selectedUserID: UUID,
        operation: SyncClientOperation
    ) async throws -> UUID {
        try await client
            .rpc(
                "update_daily_answer_partner_choice",
                params: EditDailyPartnerChoiceRequest(
                    instanceID: instanceID,
                    selectedUserID: selectedUserID,
                    operation: operation
                )
            )
            .execute()
            .value
    }

    func shuffleQuestion(
        slotNumber: Int,
        operation: SyncClientOperation
    ) async throws -> DailyChallengeRemoteSnapshotRow {
        try await snapshotRPC(
            "shuffle_daily_question_snapshot",
            params: ShuffleDailyQuestionRequest(
                slotNumber: slotNumber,
                operation: operation
            )
        )
    }
}

nonisolated enum DailyChallengeServiceFactory {
    static func makeDefault() -> any DailyChallengeServicing {
        guard let service = try? SupabaseDailyChallengeService.live() else {
            return EmptyDailyChallengeService()
        }
        return service
    }
}

private actor EmptyDailyChallengeService: DailyChallengeServicing {
    func loadToday(currentUserID: UUID) async throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }

    func startToday(
        currentUserID: UUID,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }

    func loadHistory(currentUserID _: UUID) async throws -> [DailyChallengeQuestion] {
        []
    }

    func loadStreak() async throws -> CoupleStreak {
        .none
    }

    func editTextAnswer(
        instanceID _: UUID,
        text _: String,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func editPartnerChoice(
        instanceID _: UUID,
        selectedUserID _: UUID,
        operation _: SyncClientOperation
    ) async throws -> UUID {
        throw DailyChallengeServiceUnavailableError()
    }

    func shuffleQuestion(
        currentUserID: UUID,
        slotNumber _: Int,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeLoadResult {
        DailyChallengeLoadResult(snapshot: .empty(currentUserID: currentUserID), streak: .none)
    }
}

nonisolated struct DailyChallengeServiceUnavailableError: Error, Equatable, Sendable {}

/// Raised when the backend rejects a question swap because the user has already
/// used all of today's swaps. The view model maps this to a friendly message.
nonisolated struct DailyChallengeShuffleLimitError: Error, Equatable, Sendable {}

/// Raised when an answer can no longer be edited because the partner has already
/// answered the same question (so the content is revealed).
nonisolated struct DailyChallengeEditLockedError: Error, Equatable, Sendable {}

nonisolated private struct DailyChallengeClientOperationRequest: Encodable {
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(operation: SyncClientOperation) {
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated private struct DailyAnswerDetailsRequest: Encodable {
    let coupleDayID: UUID

    enum CodingKeys: String, CodingKey {
        case coupleDayID = "p_couple_day_id"
    }
}

nonisolated private struct SubmitDailyAnswerRequest: Encodable {
    let instanceID: UUID
    let payload: DailyAnswerPayloadBody
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(instanceID: UUID, answerID: UUID, payload: DailyAnswerPayload, operation: SyncClientOperation) {
        self.instanceID = instanceID
        self.payload = DailyAnswerPayloadBody(answerID: answerID, payload: payload)
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
        case payload = "p_payload"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

/// Encodes the `p_payload` JSON the backend expects, carrying a client-generated
/// `answer_id` for idempotency plus the per-kind fields. Only text is sent today;
/// partner-choice and media fields are added with their features.
nonisolated private struct DailyAnswerPayloadBody: Encodable {
    let answerID: UUID
    let payload: DailyAnswerPayload

    enum CodingKeys: String, CodingKey {
        case answerID = "answer_id"
        case text
        case partnerChoiceUserID = "partner_choice_user_id"
        case mediaAssetIDs = "media_asset_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(answerID, forKey: .answerID)
        // Any combination the backend allows: a text body, a partner pick, and/or
        // media ids — only the parts that are present are sent.
        if let text = payload.text {
            try container.encode(text, forKey: .text)
        }
        if let userID = payload.partnerChoiceUserID {
            try container.encode(userID, forKey: .partnerChoiceUserID)
        }
        if !payload.mediaAssetIDs.isEmpty {
            try container.encode(payload.mediaAssetIDs, forKey: .mediaAssetIDs)
        }
    }
}

nonisolated private struct EditDailyTextAnswerRequest: Encodable {
    let instanceID: UUID
    let text: String
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(instanceID: UUID, text: String, operation: SyncClientOperation) {
        self.instanceID = instanceID
        self.text = text
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
        case text = "p_text"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated private struct EditDailyPartnerChoiceRequest: Encodable {
    let instanceID: UUID
    let selectedUserID: UUID
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(instanceID: UUID, selectedUserID: UUID, operation: SyncClientOperation) {
        self.instanceID = instanceID
        self.selectedUserID = selectedUserID
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case instanceID = "p_instance_id"
        case selectedUserID = "p_selected_user_id"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

nonisolated private struct ShuffleDailyQuestionRequest: Encodable {
    let slotNumber: Int
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(slotNumber: Int, operation: SyncClientOperation) {
        self.slotNumber = slotNumber
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case slotNumber = "p_slot_number"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }
}

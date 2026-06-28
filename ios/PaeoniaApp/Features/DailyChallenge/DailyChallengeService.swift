import Foundation
import Supabase

protocol DailyChallengeServicing: Actor {
    func loadToday(currentUserID: UUID) async throws -> DailyChallengeSnapshot
    func startToday(currentUserID: UUID, operation: SyncClientOperation) async throws -> DailyChallengeSnapshot
    func loadStreak() async throws -> CoupleStreak
    func editTextAnswer(instanceID: UUID, text: String, operation: SyncClientOperation) async throws -> UUID
    func editPartnerChoice(instanceID: UUID, selectedUserID: UUID, operation: SyncClientOperation) async throws -> UUID
    func shuffleQuestion(
        currentUserID: UUID,
        slotNumber: Int,
        operation: SyncClientOperation
    ) async throws -> DailyChallengeSnapshot
}

protocol SupabaseDailyChallengeGateway: Actor {
    func loadTodayQuestions() async throws -> [DailyQuestionRow]
    func startDailyChallenge(operation: SyncClientOperation) async throws -> [DailyQuestionRow]
    func loadCoupleStreak() async throws -> CoupleStreak
    func loadAnswerDetails(coupleDayID: UUID) async throws -> [DailyAnswerDetailRow]
    func submitAnswer(instanceID: UUID, answerID: UUID, payload: DailyAnswerPayload, operation: SyncClientOperation) async throws -> UUID
    func editTextAnswer(instanceID: UUID, text: String, operation: SyncClientOperation) async throws -> UUID
    func editPartnerChoice(instanceID: UUID, selectedUserID: UUID, operation: SyncClientOperation) async throws -> UUID
    func shuffleQuestion(slotNumber: Int, operation: SyncClientOperation) async throws -> [DailyQuestionRow]
}

actor SupabaseDailyChallengeService: DailyChallengeServicing {
    private let gateway: any SupabaseDailyChallengeGateway
    private let locale: Locale

    init(
        gateway: any SupabaseDailyChallengeGateway,
        locale: Locale = .current
    ) {
        self.gateway = gateway
        self.locale = locale
    }

    static func live() throws -> SupabaseDailyChallengeService {
        let client = try PaeoniaSupabaseClientProvider.shared.client()
        return SupabaseDailyChallengeService(
            gateway: LiveSupabaseDailyChallengeGateway(client: client)
        )
    }

    func loadToday(currentUserID: UUID) async throws -> DailyChallengeSnapshot {
        let rows = try await gateway.loadTodayQuestions()
        return try await snapshot(currentUserID: currentUserID, rows: rows)
    }

    func startToday(
        currentUserID: UUID,
        operation: SyncClientOperation
    ) async throws -> DailyChallengeSnapshot {
        let rows = try await gateway.startDailyChallenge(operation: operation)
        return try await snapshot(currentUserID: currentUserID, rows: rows)
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
    ) async throws -> DailyChallengeSnapshot {
        let rows: [DailyQuestionRow]
        do {
            rows = try await gateway.shuffleQuestion(slotNumber: slotNumber, operation: operation)
        } catch {
            // The backend caps each person at a few swaps per day. Translate that
            // one specific case into a typed error so the UI can show a friendly,
            // non-technical message instead of a generic failure.
            if String(describing: error).contains("daily shuffle limit reached") {
                throw DailyChallengeShuffleLimitError()
            }
            throw error
        }
        return try await snapshot(currentUserID: currentUserID, rows: rows)
    }

    private func snapshot(
        currentUserID: UUID,
        rows: [DailyQuestionRow]
    ) async throws -> DailyChallengeSnapshot {
        guard let coupleDayID = rows.first?.coupleDayID else {
            return .empty(currentUserID: currentUserID)
        }

        let answerDetails = try await gateway.loadAnswerDetails(coupleDayID: coupleDayID)
        return DailyChallengeSnapshot.make(
            currentUserID: currentUserID,
            rows: rows,
            answerDetails: answerDetails,
            locale: locale
        )
    }
}

actor LiveSupabaseDailyChallengeGateway: SupabaseDailyChallengeGateway {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadTodayQuestions() async throws -> [DailyQuestionRow] {
        try await client
            .rpc("get_today_daily_questions")
            .execute()
            .value
    }

    func startDailyChallenge(operation: SyncClientOperation) async throws -> [DailyQuestionRow] {
        try await client
            .rpc(
                "start_daily_challenge",
                params: DailyChallengeClientOperationRequest(operation: operation)
            )
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
    ) async throws -> [DailyQuestionRow] {
        try await client
            .rpc(
                "shuffle_daily_question",
                params: ShuffleDailyQuestionRequest(
                    slotNumber: slotNumber,
                    operation: operation
                )
            )
            .execute()
            .value
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
    func loadToday(currentUserID: UUID) async throws -> DailyChallengeSnapshot {
        .empty(currentUserID: currentUserID)
    }

    func startToday(
        currentUserID: UUID,
        operation _: SyncClientOperation
    ) async throws -> DailyChallengeSnapshot {
        .empty(currentUserID: currentUserID)
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
    ) async throws -> DailyChallengeSnapshot {
        .empty(currentUserID: currentUserID)
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

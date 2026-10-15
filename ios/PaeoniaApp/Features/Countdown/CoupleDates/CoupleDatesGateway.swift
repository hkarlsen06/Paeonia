import Foundation

/// The countdown and birthday backend functions (`backend/convex/countdowns.ts`).
nonisolated protocol CoupleDatesGateway: Sendable {
    /// Creates or edits a countdown. Returns it as stored, or nil when it was deleted.
    func saveCountdown(_ countdown: CustomCountdown, operation: SyncClientOperation) async throws -> CustomCountdown?
    func deleteCountdown(id: UUID, operation: SyncClientOperation) async throws
    /// Returns the birthday as stored.
    func setBirthday(_ payload: SetBirthdayPayload, operation: SyncClientOperation) async throws -> RemoteBirthdayResult
}

nonisolated struct LiveCoupleDatesGateway: CoupleDatesGateway {
    let client: PaeoniaConvexClient

    func saveCountdown(_ countdown: CustomCountdown, operation: SyncClientOperation) async throws -> CustomCountdown? {
        try await client.mutation(
            "countdowns:save_countdown",
            args: SaveCountdownRequest(countdown: countdown, operation: GameClientOperationFields(operation))
        )
    }

    func deleteCountdown(id: UUID, operation: SyncClientOperation) async throws {
        try await client.mutation(
            "countdowns:delete_countdown",
            args: DeleteCountdownRequest(id: id, operation: GameClientOperationFields(operation))
        )
    }

    func setBirthday(
        _ payload: SetBirthdayPayload,
        operation: SyncClientOperation
    ) async throws -> RemoteBirthdayResult {
        try await client.mutation(
            "countdowns:set_birthday",
            args: SetBirthdayRequest(payload: payload, operation: GameClientOperationFields(operation))
        )
    }
}

nonisolated private struct SaveCountdownRequest: Encodable {
    let countdown: CustomCountdown
    let operation: GameClientOperationFields

    enum CodingKeys: String, CodingKey {
        case id = "p_countdown_id"
        case title = "p_title"
        case targetDate = "p_target_date"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(countdown.id, forKey: .id)
        try container.encode(countdown.title, forKey: .title)
        try container.encode(countdown.targetDate, forKey: .targetDate)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct DeleteCountdownRequest: Encodable {
    let id: UUID
    let operation: GameClientOperationFields

    enum CodingKeys: String, CodingKey {
        case id = "p_countdown_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try operation.encode(to: encoder)
    }
}

nonisolated private struct SetBirthdayRequest: Encodable {
    let payload: SetBirthdayPayload
    let operation: GameClientOperationFields

    enum CodingKeys: String, CodingKey {
        case userID = "p_user_id"
        case birthday = "p_birthday"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(payload.userID, forKey: .userID)
        // `null` removes the birthday, so it is sent rather than left out.
        try container.encode(payload.birthday, forKey: .birthday)
        try operation.encode(to: encoder)
    }
}

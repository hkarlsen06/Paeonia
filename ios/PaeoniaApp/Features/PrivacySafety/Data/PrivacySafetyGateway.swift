import Foundation

nonisolated protocol PrivacySafetyGateway: Actor {
    func loadPrivacyRequests() async throws -> [PrivacyRequestRemoteRow]

    func createPrivacyRequest(
        id: UUID,
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) async throws -> PrivacyRequestRemoteRow

    func submitReportAndLeave(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) async throws -> UUID
}

actor LivePrivacySafetyGateway: PrivacySafetyGateway {
    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    func loadPrivacyRequests() async throws -> [PrivacyRequestRemoteRow] {
        try await client.query("identity:get_privacy_requests")
    }

    func createPrivacyRequest(
        id: UUID,
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) async throws -> PrivacyRequestRemoteRow {
        try await client.mutation(
            "identity:create_privacy_request",
            args: CreatePrivacyRequestArguments(
                id: id,
                kind: kind,
                requesterNote: requesterNote
            )
        )
    }

    func submitReportAndLeave(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) async throws -> UUID {
        // The backend derives the reporter and active relationship from the
        // signed-in user. Requiring the session locally prevents an anonymous
        // safety request that cannot end access from looking like it was submitted.
        try await PaeoniaSignedIn.require(isSignedIn)

        return try await client.mutation(
            "reports:submit_leave_and_report",
            args: SubmitReportAndLeaveRequest(
                target: target,
                reason: reason,
                note: note,
                blockPartner: blockPartner,
                operation: operation
            )
        )
    }
}

nonisolated private struct CreatePrivacyRequestArguments: Encodable {
    let id: UUID
    let kind: PrivacyRequestKind
    let requesterNote: String?

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case kind = "p_kind"
        case requesterNote = "p_requester_note"
    }
}

nonisolated struct SubmitReportAndLeaveRequest: Encodable {
    let reason: PrivacyReportReason
    let note: String?
    let targetKind: String
    let targetID: UUID
    let targetAuxID: UUID? = nil
    let blockReportedUser: Bool
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) {
        self.reason = reason
        self.note = note
        self.targetKind = target.kind
        self.targetID = target.id
        self.blockReportedUser = blockPartner
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case reason = "p_reason"
        case note = "p_note"
        case targetKind = "p_target_kind"
        case targetID = "p_target_id"
        case targetAuxID = "p_target_aux_id"
        case blockReportedUser = "p_block_reported_user"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reason, forKey: .reason)
        if let note {
            try container.encode(note, forKey: .note)
        } else {
            try container.encodeNil(forKey: .note)
        }
        try container.encode(targetKind, forKey: .targetKind)
        try container.encode(targetID, forKey: .targetID)
        try container.encodeNil(forKey: .targetAuxID)
        try container.encode(blockReportedUser, forKey: .blockReportedUser)
        try container.encode(clientOperationID, forKey: .clientOperationID)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(clientSequence, forKey: .clientSequence)
        try container.encode(localCreatedAt, forKey: .localCreatedAt)
    }
}

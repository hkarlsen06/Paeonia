import Foundation
import Supabase

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
    private enum Constants {
        static let privacyRequestColumns = "id,request_kind,status,requested_at,visible_status_message"
    }

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadPrivacyRequests() async throws -> [PrivacyRequestRemoteRow] {
        let session = try await client.auth.session

        return try await client
            .from("privacy_requests")
            .select(Constants.privacyRequestColumns)
            .eq("user_id", value: session.user.id.uuidString)
            .order("requested_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func createPrivacyRequest(
        id: UUID,
        kind: PrivacyRequestKind,
        requesterNote: String?
    ) async throws -> PrivacyRequestRemoteRow {
        let session = try await client.auth.session
        let insert = PrivacyRequestInsert(
            id: id,
            userID: session.user.id,
            requestKind: kind,
            requesterNote: requesterNote
        )

        return try await client
            .from("privacy_requests")
            .insert(insert)
            .select(Constants.privacyRequestColumns)
            .single()
            .execute()
            .value
    }

    func submitReportAndLeave(
        target: PrivacyReportTarget,
        reason: PrivacyReportReason,
        note: String?,
        blockPartner: Bool,
        operation: SyncClientOperation
    ) async throws -> UUID {
        // This RPC derives the reporter and active relationship from auth.uid().
        // Requiring the session locally prevents an anonymous safety request that
        // cannot end access from looking like it was submitted.
        _ = try await client.auth.session

        return try await client
            .rpc(
                "submit_leave_and_report",
                params: SubmitReportAndLeaveRequest(
                    target: target,
                    reason: reason,
                    note: note,
                    blockPartner: blockPartner,
                    operation: operation
                )
            )
            .execute()
            .value
    }
}

nonisolated private struct PrivacyRequestInsert: Encodable {
    let id: UUID
    let userID: UUID
    let requestKind: PrivacyRequestKind
    let requesterNote: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case requestKind = "request_kind"
        case requesterNote = "requester_note"
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

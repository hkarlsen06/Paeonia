import Foundation

nonisolated enum PrivacyRequestKind: String, CaseIterable, Codable, Hashable, Sendable {
    case access
    case export
    case correction
}

nonisolated enum PrivacyRequestStatus: String, Codable, Hashable, Sendable {
    case submitted
    case verifying
    case processing
    case completed
    case rejected
    case cancelled

    var isActive: Bool {
        switch self {
        case .submitted, .verifying, .processing:
            true
        case .completed, .rejected, .cancelled:
            false
        }
    }
}

nonisolated struct PrivacyRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: PrivacyRequestKind
    let status: PrivacyRequestStatus
    let requestedAt: Date
    let visibleStatusMessage: String?

    var isActive: Bool {
        status.isActive
    }
}

nonisolated enum PrivacyRequestSubmissionOutcome: Equatable, Sendable {
    case created(PrivacyRequest)
    case alreadyActive(PrivacyRequest)

    var request: PrivacyRequest {
        switch self {
        case let .created(request), let .alreadyActive(request):
            request
        }
    }
}

nonisolated enum PrivacyReportReason: String, CaseIterable, Codable, Hashable, Sendable {
    case harassment
    case abuse
    case threat
    case sexualContent = "sexual_content"
    case hate
    case privacy
    case impersonation
    case selfHarm = "self_harm"
    case spam
    case other
}

/// The existing reporting RPC accepts several kinds of relationship content. Keep
/// that wire detail here so every entry point still opens the same report-and-leave
/// flow while preserving the specific content the user reported.
nonisolated enum PrivacyReportTarget: Equatable, Sendable {
    case conduct(userID: UUID)
    case dailyAnswer(answerID: UUID)

    var kind: String {
        switch self {
        case .conduct:
            "conduct"
        case .dailyAnswer:
            "daily_answer"
        }
    }

    var id: UUID {
        switch self {
        case let .conduct(userID):
            userID
        case let .dailyAnswer(answerID):
            answerID
        }
    }
}

nonisolated struct PrivacyRequestRemoteRow: Decodable, Equatable, Sendable {
    let id: UUID
    let requestKind: PrivacyRequestKind
    let status: PrivacyRequestStatus
    let requestedAt: Date
    let visibleStatusMessage: String?

    var request: PrivacyRequest {
        PrivacyRequest(
            id: id,
            kind: requestKind,
            status: status,
            requestedAt: requestedAt,
            visibleStatusMessage: visibleStatusMessage
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case requestKind = "request_kind"
        case status
        case requestedAt = "requested_at"
        case visibleStatusMessage = "visible_status_message"
    }
}

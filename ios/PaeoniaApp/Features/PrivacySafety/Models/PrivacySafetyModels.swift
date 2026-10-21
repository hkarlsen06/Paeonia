import Foundation

/// Asking to see or copy your data is not a request: "Download my data" answers
/// it at once (`DataExportService`). What is left needs a person at Paeonia.
nonisolated enum PrivacyRequestKind: String, CaseIterable, Codable, Hashable, Sendable {
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

    /// Reasons where the person writing may be in danger right now, so the form
    /// points them to emergency help before they send anything.
    var suggestsEmergencyHelp: Bool {
        switch self {
        case .threat, .selfHarm:
            true
        case .harassment, .abuse, .sexualContent, .hate, .privacy, .impersonation, .spam, .other:
            false
        }
    }
}

/// The existing reporting RPC accepts several kinds of relationship content. Keep
/// that wire detail here so every entry point still opens the same report-and-leave
/// flow while preserving the specific content the user reported.
nonisolated enum PrivacyReportTarget: Hashable, Sendable {
    case conduct(userID: UUID)
    case dailyAnswer(answerID: UUID)
    case threadMessage(messageID: UUID)

    var kind: String {
        switch self {
        case .conduct:
            "conduct"
        case .dailyAnswer:
            "daily_answer"
        case .threadMessage:
            "thread_message"
        }
    }

    var id: UUID {
        switch self {
        case let .conduct(userID):
            userID
        case let .dailyAnswer(answerID):
            answerID
        case let .threadMessage(messageID):
            messageID
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

/// The list `get_privacy_requests` returns. The server can add request kinds or
/// statuses before every installed app knows them (for example account deletion),
/// so a row this version cannot read is skipped instead of failing the whole list.
nonisolated struct PrivacyRequestRemoteRows: Decodable, Sendable {
    let rows: [PrivacyRequestRemoteRow]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var rows = [PrivacyRequestRemoteRow]()
        while !container.isAtEnd {
            if let row = try? container.decode(PrivacyRequestRemoteRow.self) {
                rows.append(row)
            } else {
                // A failed decode does not move the container forward. Decoding a
                // type that accepts anything consumes the unreadable element.
                _ = try container.decode(PaeoniaConvexIgnoredResult.self)
            }
        }
        self.rows = rows
    }
}

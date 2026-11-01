import Foundation

/// Privacy state for the Home Screen widget. `redacted` tells every renderer to
/// show a neutral placeholder instead of the drawing.
nonisolated enum WidgetSharePrivacyMode: String, Codable, Equatable, Sendable {
    case normal
    case redacted
}

/// Lightweight metadata the app writes into the App Group container for the
/// widget to read. This is local cache only: it never contains canonical
/// `PKDrawing` data or note text. The authored drawing description is private
/// content and follows the same redaction and purge rules as the previews.
///
/// Both targets use this contract for atomic reads and locked metadata writes.
nonisolated struct WidgetSharePayload: Codable, Equatable {
    nonisolated static let currentSchemaVersion = 1
    nonisolated static let currentRendererVersion = 1

    var schemaVersion = WidgetSharePayload.currentSchemaVersion
    var revisionID: String
    /// Identifies the exact local publication independently of later description corrections.
    var localPublicationID: UUID?
    /// Display name of whoever saved this drawing, shown on the widget. This is
    /// the only identity detail in the payload; keep other private content out.
    let authorName: String?
    let createdAt: Date
    let renderedAt: Date
    var rendererVersion = WidgetSharePayload.currentRendererVersion
    /// Every writer must choose visibility explicitly. Readers display content only
    /// when both fields permit it, after the publication path validates access.
    var privacyMode: WidgetSharePrivacyMode
    var isRedacted: Bool
    let contentHash: String
    let previews: [String: String]
    /// Side of the square canvas the drawing was made on. The app reads it to
    /// scale the drawing on a phone with a different screen size. The widget
    /// ignores it.
    let canvasSide: Double
    var accessibilityText: String?
    /// The server version installed as visible text. A newer version can wait behind a pending edit.
    var descriptionVersion: Int64?
    /// Keeps stale live reads from replacing a correction waiting in the durable outbox.
    var pendingDescriptionOperationID: UUID?
    /// The newest server state stays durable behind the local pending text.
    var deferredDescription: WidgetDrawingServerDescription?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revisionID = "revisionId"
        case localPublicationID
        case authorName
        case createdAt
        case renderedAt
        case rendererVersion
        case privacyMode
        case isRedacted
        case contentHash
        case previews
        case accessibilityText, descriptionVersion, pendingDescriptionOperationID, deferredDescription
        case canvasSide
    }

    nonisolated static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

nonisolated enum WidgetDrawingDescriptionUpdate: Sendable {
    case queued(text: String, operationID: UUID)
    case accepted(text: String?, version: Int64, operationID: UUID)
    /// The outbox and ordered cache writer verified that this is the latest durable operation.
    case acceptedLatestPending(text: String?, version: Int64, operationID: UUID)
    case remote(text: String?, version: Int64)
}

nonisolated extension WidgetSharePayload {
    /// Re-read under the publication lock. Never write a caller's earlier snapshot back.
    static func updateFile(in containerURL: URL, _ update: (inout Self) throws -> Void) throws -> Bool {
        try WidgetPayloadFileLock.withExclusiveAccess(in: containerURL) {
            let url = containerURL.appendingPathComponent("Widget/current.json")
            let bytes: Data
            do {
                bytes = try Data(contentsOf: url)
            } catch CocoaError.fileReadNoSuchFile {
                return false
            }
            var current = try decoder().decode(Self.self, from: bytes)
            let previous = current
            try update(&current)
            guard current != previous else { return false }
            try encoder().encode(current).write(to: url, options: .atomic)
            return true
        }
    }

    private static func cleanedDescription(_ text: String?) -> String? {
        guard let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else { return nil }
        return cleaned
    }

    mutating func applyDescription(_ update: WidgetDrawingDescriptionUpdate) {
        switch update {
        case let .queued(text, operationID):
            if pendingDescriptionOperationID == nil, let descriptionVersion {
                deferredDescription = WidgetDrawingServerDescription(
                    text: accessibilityText, version: descriptionVersion
                )
            }
            accessibilityText = Self.cleanedDescription(text)
            pendingDescriptionOperationID = operationID
        case let .accepted(text, version, operationID):
            rememberServerDescription(text, version: version)
            // Complete only this optimistic edit, then reveal the newest server state already received.
            guard pendingDescriptionOperationID == operationID, let deferredDescription else { return }
            accessibilityText = deferredDescription.text
            descriptionVersion = deferredDescription.version
            pendingDescriptionOperationID = nil
            self.deferredDescription = nil
        case let .acceptedLatestPending(text, version, operationID):
            // An optimistic write may have failed after the operation reached the outbox.
            // Restore that overlay inside this same atomic write before completing it.
            if pendingDescriptionOperationID != operationID {
                applyDescription(.queued(text: text ?? "", operationID: operationID))
            }
            applyDescription(.accepted(text: text, version: version, operationID: operationID))
        case let .remote(text, version):
            rememberServerDescription(text, version: version)
        }
    }

    private mutating func rememberServerDescription(_ text: String?, version: Int64) {
        guard descriptionVersion.map({ version >= $0 }) ?? true,
              deferredDescription.map({ version >= $0.version }) ?? true else { return }
        let cleaned = Self.cleanedDescription(text)
        if pendingDescriptionOperationID != nil {
            deferredDescription = WidgetDrawingServerDescription(text: cleaned, version: version)
        } else {
            accessibilityText = cleaned
            descriptionVersion = version
            deferredDescription = nil
        }
    }
}

nonisolated struct WidgetDrawingServerDescription: Codable, Equatable, Sendable {
    let text: String?
    let version: Int64
}

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
    let revisionID: String
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
    /// Nil while the drawing has not received a server description version.
    var descriptionVersion: Int64?
    /// Keeps stale live reads from replacing a correction waiting in the durable outbox.
    var pendingDescriptionOperationID: UUID?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revisionID = "revisionId"
        case authorName
        case createdAt
        case renderedAt
        case rendererVersion
        case privacyMode
        case isRedacted
        case contentHash
        case previews
        case accessibilityText, descriptionVersion, pendingDescriptionOperationID
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
    case remote(text: String?, version: Int64)
}

nonisolated extension WidgetSharePayload {
    /// Re-read under the publication lock. Never write a caller's earlier snapshot back.
    static func updateFile(in containerURL: URL, _ update: (inout Self) throws -> Void) throws -> Bool {
        try WidgetPayloadFileLock.withExclusiveAccess(in: containerURL) {
            let url = containerURL.appendingPathComponent("Widget/current.json")
            guard let bytes = try? Data(contentsOf: url),
                  var current = try? decoder().decode(Self.self, from: bytes) else { return false }
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
            accessibilityText = Self.cleanedDescription(text)
            pendingDescriptionOperationID = operationID
        case let .accepted(text, version, operationID):
            guard pendingDescriptionOperationID == nil || pendingDescriptionOperationID == operationID,
                  descriptionVersion.map({ version >= $0 }) ?? true else { return }
            accessibilityText = Self.cleanedDescription(text)
            descriptionVersion = version
            pendingDescriptionOperationID = nil
        case let .remote(text, version):
            guard pendingDescriptionOperationID == nil,
                  descriptionVersion.map({ version >= $0 }) ?? true else { return }
            accessibilityText = Self.cleanedDescription(text)
            descriptionVersion = version
        }
    }
}

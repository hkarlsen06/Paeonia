import Foundation

/// Privacy state for the Home Screen widget. `redacted` tells every renderer to
/// show a neutral placeholder instead of the drawing.
nonisolated enum WidgetSharePrivacyMode: String, Codable, Equatable, Sendable {
    case normal
    case redacted
}

/// Lightweight metadata the app writes into the App Group container for the
/// widget to read. This is local cache only: it never contains canonical
/// `PKDrawing` data, note text, or other private content beyond the rendered
/// preview images it points at.
///
/// The field names and JSON shape must stay compatible with the decoder in the
/// widget target (`PaeoniaWidgetStore`).
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
    /// Safe by default: payload construction starts redacted. The save pipeline
    /// must explicitly opt a validated, user-saved drawing into Home Screen
    /// display with `.normal` and `isRedacted = false`.
    var privacyMode: WidgetSharePrivacyMode = .redacted
    var isRedacted = true
    let contentHash: String
    let previews: [String: String]

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

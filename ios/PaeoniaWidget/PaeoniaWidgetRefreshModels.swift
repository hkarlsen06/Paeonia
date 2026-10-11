// The app target compiles every file in this folder that its project exception
// list does not name. Only the extension refreshes, so the flag keeps these
// types out of the app.
#if WIDGET_EXTENSION
import Foundation
import PencilKit

extension PaeoniaWidgetRefreshService {
    enum RefreshError: Error {
        case missingConfiguration
        case notSignedIn
        case unavailableAppGroup
        case renderFailed
        /// The user signed out or the app purged the widget during the refresh.
        case privacyChanged
        /// The app saved a newer local drawing during the refresh.
        case superseded
    }

    struct PendingUpload: Decodable {
        let contentHash: String
    }

    /// The fields of `Widget/current.json` needed to tell whether the widget
    /// already shows a revision.
    struct StoredPayload: Decodable {
        let revisionID: String
        let privacyMode: String
        let isRedacted: Bool
        let previews: [String: String]

        enum CodingKeys: String, CodingKey {
            case revisionID = "revisionId"
            case privacyMode
            case isRedacted
            case previews
        }
    }

    struct CanvasState: Decodable {
        let activeRevisionID: UUID?
        let activeRevisionAuthorUserID: UUID?
        let payloadMediaAssetID: UUID?
        let bounds: DrawingBounds?
        let revisionCreatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case activeRevisionID = "active_revision_id"
            case activeRevisionAuthorUserID = "active_revision_author_user_id"
            case payloadMediaAssetID = "payload_media_asset_id"
            case bounds
            case revisionCreatedAt = "revision_created_at"
        }
    }

    struct DrawingBounds: Decodable {
        let canvasSide: Double
    }

    struct SignedURLRequest: Encodable {
        let mediaAssetID: UUID
        let expiresInSeconds = 900

        enum CodingKeys: String, CodingKey {
            case mediaAssetID = "p_media_asset_id"
            case expiresInSeconds = "p_expires_in_seconds"
        }
    }

    struct SignedURLAuthorization: Decodable {
        let signedURL: URL

        enum CodingKeys: String, CodingKey {
            case signedURL = "signed_url"
        }
    }

    struct PreviewSpec {
        let family: String
        let pixelWidth: Double

        static let all = [
            PreviewSpec(family: "systemSmall", pixelWidth: 480),
            PreviewSpec(family: "systemLarge", pixelWidth: 880),
        ]
    }

    struct RemoteDrawing {
        let drawing: PKDrawing
        let contentHash: String
        let canvasSide: Double
        let revisionID: UUID
        let authorUserID: UUID?
        let createdAt: Date
    }

    struct CurrentPayload: Codable {
        let schemaVersion = 1
        let revisionID: String
        let authorName: String?
        let createdAt: Date
        let renderedAt: Date
        let rendererVersion = 1
        let privacyMode = "normal"
        let isRedacted = false
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

        static var encoder: JSONEncoder {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return encoder
        }

        static var decoder: JSONDecoder {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }
    }

    struct WidgetIdentity {
        let currentUserID: UUID?
        let currentDisplayName: String?
        let partnerDisplayName: String?

        static func load() -> WidgetIdentity {
            let defaults = UserDefaults(suiteName: appGroupIdentifier)
            return WidgetIdentity(
                currentUserID: defaults?
                    .string(forKey: "paeonia.widgetSync.currentUserID")
                    .flatMap(UUID.init(uuidString:)),
                currentDisplayName: defaults?
                    .string(forKey: "paeonia.widgetSync.currentDisplayName"),
                partnerDisplayName: defaults?
                    .string(forKey: "paeonia.widgetSync.partnerDisplayName")
            )
        }

        func authorName(for authorUserID: UUID?) -> String? {
            authorUserID == currentUserID ? currentDisplayName : partnerDisplayName
        }
    }
}
#endif

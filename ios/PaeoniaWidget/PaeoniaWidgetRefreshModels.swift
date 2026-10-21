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
        /// The inviter's own first drawing, which belongs to no couple yet.
        let isFirstDay: Bool
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
        /// What this person calls the author, decided by the server (their nickname for the
        /// partner when they set one).
        let activeRevisionAuthorName: String?
        let payloadMediaAssetID: UUID?
        let bounds: DrawingBounds?
        let revisionCreatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case activeRevisionID = "active_revision_id"
            case activeRevisionAuthorName = "active_revision_author_name"
            case payloadMediaAssetID = "payload_media_asset_id"
            case bounds
            case revisionCreatedAt = "revision_created_at"
        }
    }

    struct DrawingBounds: Decodable {
        let canvasSide: Double?
    }

    /// The part of `firstDay:get_first_day_draft` the widget needs: the person's own
    /// first drawing, saved before any partner joined.
    struct FirstDayDraftState: Decodable {
        let drawing: FirstDayDrawing?
    }

    struct FirstDayDrawing: Decodable {
        let mediaAssetID: UUID
        let revisionID: UUID
        let savedAt: Date
        let bounds: DrawingBounds?

        enum CodingKeys: String, CodingKey {
            case mediaAssetID = "media_asset_id"
            case revisionID = "revision_id"
            case savedAt = "saved_at"
            case bounds
        }
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
        let authorName: String?
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
        /// The app requires this to read the payload, so leaving it out shows
        /// the empty sketch on the app's home card.
        let canvasSide: Double

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
            case canvasSide
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

    /// The person's own name, saved by the app. A first-day drawing has no partner, so the server
    /// has no author name to give.
    struct WidgetIdentity {
        let currentDisplayName: String?

        static func load() -> WidgetIdentity {
            WidgetIdentity(
                currentDisplayName: UserDefaults(suiteName: appGroupIdentifier)?
                    .string(forKey: "paeonia.widgetSync.currentDisplayName")
            )
        }
    }
}
#endif

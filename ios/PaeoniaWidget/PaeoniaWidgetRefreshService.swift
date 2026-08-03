import CryptoKit
import Foundation
import PencilKit
import Supabase
import UIKit

/// Performs the small authenticated read needed by the interactive widget.
/// Session refresh is handled by Supabase using the keychain access group shared
/// with the host app.
enum PaeoniaWidgetRefreshService {
    private static let appGroupIdentifier = "group.no.paeonia.app"
    private static let authStorageKey = "paeonia-auth-session"
    private static let authAccessGroup = "48ZSLD4RMP.no.paeonia.shared"
    private static let payloadPath = "Widget/current.json"
    private static let previewsDirectory = "Widget/Previews"
    private static let pendingUploadKey = "paeonia.widgetCanvas.pendingUpload"
    private static let legacyPendingUploadHashKey = "paeonia.widgetCanvas.pendingUploadHash"

    @MainActor
    static func refresh() async throws {
        let client = try makeClient()
        _ = try await client.auth.session
        guard let remoteDrawing = try await loadRemoteDrawing(client: client),
              shouldPublish(remoteContentHash: contentHash(for: remoteDrawing.drawingData))
        else {
            return
        }
        try publish(remoteDrawing)
    }

    @MainActor
    private static func loadRemoteDrawing(client: SupabaseClient) async throws -> RemoteDrawing? {
        let states: [CanvasState] = try await client
            .rpc("get_widget_canvas", params: EmptyRequest())
            .execute()
            .value
        guard let state = states.first,
              let revisionID = state.activeRevisionID,
              let mediaAssetID = state.payloadMediaAssetID
        else {
            return nil
        }

        let signedURL = try await signedPayloadURL(
            client: client,
            mediaAssetID: mediaAssetID
        )
        guard let signedURL else { return nil }
        let (drawingData, response) = try await URLSession.shared.data(from: signedURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let drawing = try? PKDrawing(data: drawingData)
        else {
            return nil
        }

        return RemoteDrawing(
            drawing: drawing,
            drawingData: drawingData,
            canvasSide: state.bounds?.canvasSide ?? 1_024,
            revisionID: revisionID,
            authorUserID: state.activeRevisionAuthorUserID,
            createdAt: state.revisionCreatedAt ?? .now
        )
    }

    private static func signedPayloadURL(
        client: SupabaseClient,
        mediaAssetID: UUID
    ) async throws -> URL? {
        let authorizations: [SignedURLAuthorization] = try await client
            .rpc(
                "get_media_signed_url",
                params: SignedURLRequest(mediaAssetID: mediaAssetID)
            )
            .execute()
            .value
        guard let authorization = authorizations.first else {
            return nil
        }

        return try await client.storage
            .from(authorization.bucket)
            .createSignedURL(
                path: authorization.storagePath,
                expiresIn: authorization.expiresInSeconds
            )
    }

    private static func makeClient() throws -> SupabaseClient {
        guard let urlString = Bundle.main.object(
            forInfoDictionaryKey: "PaeoniaSupabaseURL"
        ) as? String,
              let url = URL(string: urlString),
              let publishableKey = Bundle.main.object(
                forInfoDictionaryKey: "PaeoniaSupabasePublishableKey"
              ) as? String
        else {
            throw RefreshError.missingConfiguration
        }

        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: publishableKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: KeychainLocalStorage(
                        service: "supabase.gotrue.swift",
                        accessGroup: authAccessGroup
                    ),
                    storageKey: authStorageKey,
                    autoRefreshToken: true,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    @MainActor
    private static func publish(_ remoteDrawing: RemoteDrawing) throws {
        guard remoteDrawing.canvasSide > 0,
              let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
              )
        else {
            throw RefreshError.unavailableAppGroup
        }

        let previewsURL = containerURL.appendingPathComponent(
            previewsDirectory,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: previewsURL,
            withIntermediateDirectories: true
        )

        let previews = try renderPreviews(
            remoteDrawing,
            into: previewsURL
        )
        let identity = WidgetIdentity.load()
        let authorName = identity.authorName(for: remoteDrawing.authorUserID)
        let payload = CurrentPayload(
            revisionID: remoteDrawing.revisionID.uuidString.lowercased(),
            authorName: authorName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: remoteDrawing.createdAt,
            renderedAt: .now,
            contentHash: contentHash(for: remoteDrawing.drawingData),
            previews: previews
        )
        let payloadURL = containerURL.appendingPathComponent(payloadPath)
        try CurrentPayload.encoder.encode(payload).write(to: payloadURL, options: .atomic)
    }

    @MainActor
    private static func renderPreviews(
        _ remoteDrawing: RemoteDrawing,
        into previewsURL: URL
    ) throws -> [String: String] {
        var previews: [String: String] = [:]
        var stagedURLs: [URL] = []
        var didPublish = false
        defer {
            if !didPublish {
                stagedURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            }
        }

        for spec in PreviewSpec.all {
            let resolvedCanvasSide = CGFloat(remoteDrawing.canvasSide)
            let scale = max(1, CGFloat(spec.pixelWidth) / resolvedCanvasSide)
            var image: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = remoteDrawing.drawing.image(
                    from: CGRect(
                        x: 0,
                        y: 0,
                        width: resolvedCanvasSide,
                        height: resolvedCanvasSide
                    ),
                    scale: scale
                )
            }
            guard let pngData = image?.pngData() else {
                throw RefreshError.renderFailed
            }

            let fileName = [
                spec.family,
                remoteDrawing.revisionID.uuidString.lowercased(),
            ].joined(separator: "-") + ".png"
            let previewURL = previewsURL.appendingPathComponent(fileName)
            try pngData.write(to: previewURL, options: .atomic)
            stagedURLs.append(previewURL)
            previews[spec.family] = "\(previewsDirectory)/\(fileName)"
        }

        didPublish = true
        return previews
    }

    private static func shouldPublish(remoteContentHash: String) -> Bool {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        if let pendingData = defaults?.data(forKey: pendingUploadKey) {
            guard let pending = try? JSONDecoder().decode(PendingUpload.self, from: pendingData),
                  remoteContentHash == "sha256-\(pending.contentHash)"
            else {
                return false
            }

            // Matching server bytes confirm the host app's pending upload even
            // when the interactive widget performed the first successful read.
            clearPendingUploadIfMatching(pending.contentHash, defaults: defaults)
            return true
        }

        if let legacyHash = defaults?.string(
            forKey: legacyPendingUploadHashKey
        ) {
            guard remoteContentHash == "sha256-\(legacyHash)" else {
                return false
            }
            clearPendingUploadIfMatching(legacyHash, defaults: defaults)
            return true
        }

        // With no unsent local save, the server read is authoritative. Avoid
        // client/server timestamp comparisons: clock skew previously made a
        // real partner revision look older indefinitely.
        return true
    }

    private static func clearPendingUploadIfMatching(
        _ contentHash: String,
        defaults: UserDefaults?
    ) {
        if let pendingData = defaults?.data(forKey: pendingUploadKey),
           let pending = try? JSONDecoder().decode(PendingUpload.self, from: pendingData),
           pending.contentHash == contentHash {
            defaults?.removeObject(forKey: pendingUploadKey)
        }
        if defaults?.string(forKey: legacyPendingUploadHashKey) == contentHash {
            defaults?.removeObject(forKey: legacyPendingUploadHashKey)
        }
    }

    private static func contentHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return "sha256-" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension PaeoniaWidgetRefreshService {
    enum RefreshError: Error {
        case missingConfiguration
        case unavailableAppGroup
        case renderFailed
    }

    struct EmptyRequest: Encodable {}

    struct PendingUpload: Decodable {
        let contentHash: String
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
        let bucket: String
        let storagePath: String
        let expiresInSeconds: Int

        enum CodingKeys: String, CodingKey {
            case bucket
            case storagePath = "storage_path"
            case expiresInSeconds = "expires_in_seconds"
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
        let drawingData: Data
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

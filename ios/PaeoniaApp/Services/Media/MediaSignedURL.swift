import Foundation

nonisolated private struct MediaSignedURLRequest: Encodable, Sendable {
    let mediaAssetID: UUID
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
        case expiresInSeconds = "p_expires_in_seconds"
    }
}

/// A row of `media:get_media_signed_url`. `signed_url` is a plain GET URL that
/// needs no auth header.
nonisolated struct MediaSignedURLRow: Decodable, Sendable {
    let signedURL: URL

    enum CodingKeys: String, CodingKey {
        case signedURL = "signed_url"
    }
}

extension PaeoniaConvexClient {
    /// Returns a download URL for a media asset, or nil when the backend returns no row.
    nonisolated func signedMediaURL(for mediaAssetID: UUID, expiresInSeconds: Int) async throws -> URL? {
        let rows: [MediaSignedURLRow] = try await mutation(
            "media:get_media_signed_url",
            args: MediaSignedURLRequest(
                mediaAssetID: mediaAssetID,
                expiresInSeconds: expiresInSeconds
            )
        )
        return rows.first?.signedURL
    }
}

/// Remembers media assets that just failed for a reason retrying will not fix, such as
/// a missing or forbidden file or a response that is not an image. While an asset is
/// remembered, showing it again skips the signed URL request and the download. It
/// forgets the asset after `retryAfter` seconds, and a connection error is never
/// recorded, because that may pass.
nonisolated struct MediaMissLog: Sendable {
    let retryAfter: TimeInterval
    private var missedAt: [UUID: Date] = [:]

    init(retryAfter: TimeInterval = 60) {
        self.retryAfter = retryAfter
    }

    func isRecentMiss(_ mediaAssetID: UUID, now: Date = Date()) -> Bool {
        guard let missedAt = missedAt[mediaAssetID] else { return false }
        return now.timeIntervalSince(missedAt) < retryAfter
    }

    mutating func record(_ mediaAssetID: UUID, now: Date = Date()) {
        missedAt[mediaAssetID] = now
    }

    mutating func forget(_ mediaAssetID: UUID) {
        missedAt[mediaAssetID] = nil
    }

    mutating func removeAll() {
        missedAt.removeAll()
    }

    /// Whether a failed signed URL request is worth remembering. Only a lost
    /// connection or a timeout is likely to work on the next try.
    static func isLasting(_ error: any Error) -> Bool {
        !(error is URLError)
    }

    /// Whether an HTTP status means the file is not there or not allowed.
    static func isLasting(statusCode: Int) -> Bool {
        (400..<500).contains(statusCode) && statusCode != 408 && statusCode != 429
    }
}

nonisolated enum MediaDownloadCheck {
    /// Whether a download is a web page, such as the sign-in page of a captive portal
    /// that answers 200 for any address. Daily answers carry photos and voice notes,
    /// so this catches a page without needing to know which of the two was asked for.
    static func isWebPage(_ data: Data, mimeType: String?) -> Bool {
        if let mimeType, mimeType.lowercased().hasPrefix("text/") {
            return true
        }
        let first = data.first { !$0.isASCIIWhitespace }
        return first == UInt8(ascii: "<")
    }
}

private extension UInt8 {
    nonisolated var isASCIIWhitespace: Bool {
        self == 0x20 || (0x09...0x0D).contains(self)
    }
}

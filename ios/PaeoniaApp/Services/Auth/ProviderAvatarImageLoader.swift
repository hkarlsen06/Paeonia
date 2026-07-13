import Foundation

nonisolated protocol ProviderAvatarImageLoading: Sendable {
    func imageData(from url: URL) async -> Data?
}

/// Downloads a transient provider avatar without ever making its public URL
/// part of Paeonia's profile model. The response is streamed into a fixed byte
/// budget, then the existing image compressor validates/normalizes the bytes
/// before the private profile-photo upload runs.
actor HTTPSProviderAvatarImageLoader: ProviderAvatarImageLoading {
    nonisolated static let maximumByteCount = 1_500_000
    nonisolated static let requestTimeout: TimeInterval = 10

    private static let allowedMIMETypes: Set<String> = [
        "image/heic",
        "image/heif",
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp",
    ]

    private let session: URLSession

    init(session: URLSession = HTTPSProviderAvatarImageLoader.makeSession()) {
        self.session = session
    }

    func imageData(from url: URL) async -> Data? {
        guard Self.isSecureURL(url) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Self.requestTimeout

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  Self.isSecureRedirect(from: url, to: response.url),
                  Self.allowedMIMETypes.contains(response.mimeType?.lowercased() ?? ""),
                  Self.isAllowedContentLength(response.expectedContentLength)
            else {
                return nil
            }

            var data = Data()
            if response.expectedContentLength > 0 {
                data.reserveCapacity(Int(response.expectedContentLength))
            }

            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumByteCount else {
                    return nil
                }
                data.append(byte)
            }

            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }

    nonisolated static func isSecureURL(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https" && url?.host?.isEmpty == false
    }

    /// URLSession follows redirects automatically. Keep the final response on
    /// the SDK-provided HTTPS host so an open redirect cannot turn this bounded
    /// image fetch into a request to an unrelated host.
    nonisolated static func isSecureRedirect(from requestedURL: URL, to responseURL: URL?) -> Bool {
        guard isSecureURL(requestedURL),
              isSecureURL(responseURL),
              let requestedHost = requestedURL.host?.lowercased(),
              let responseHost = responseURL?.host?.lowercased()
        else {
            return false
        }

        return requestedHost == responseHost
    }

    nonisolated private static func isAllowedContentLength(_ byteCount: Int64) -> Bool {
        byteCount == NSURLSessionTransferSizeUnknown
            || (byteCount >= 0 && byteCount <= Int64(maximumByteCount))
    }

    nonisolated private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }
}

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
    private static let cancellationCheckInterval = 16_384

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
            let (bytes, response) = try await session.bytes(
                for: request,
                delegate: ProviderAvatarRedirectGuard(originalURL: url)
            )
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  Self.isSecureRedirect(from: url, to: response.url),
                  Self.allowedMIMETypes.contains(response.mimeType?.lowercased() ?? ""),
                  Self.isAllowedContentLength(response.expectedContentLength)
            else {
                return nil
            }

            // A byte array appends much faster than `Data` one byte at a time.
            var buffer = [UInt8]()
            if response.expectedContentLength > 0 {
                buffer.reserveCapacity(Int(response.expectedContentLength))
            }

            for try await byte in bytes {
                guard buffer.count < Self.maximumByteCount else {
                    return nil
                }
                buffer.append(byte)
                if buffer.count.isMultiple(of: Self.cancellationCheckInterval) {
                    try Task.checkCancellation()
                }
            }

            return buffer.isEmpty ? nil : Data(buffer)
        } catch {
            return nil
        }
    }

    nonisolated static func isSecureURL(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https" && url?.host?.isEmpty == false
    }

    /// URLSession follows redirects automatically. Keep every hop and the final
    /// response on the SDK-provided HTTPS host so an open redirect cannot turn
    /// this bounded image fetch into a request to an unrelated host.
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

/// Stops a redirect before URLSession sends the next request, so a redirect to
/// another host never receives a request. The task then ends with the redirect
/// response, which the loader rejects because it is not a 2xx.
nonisolated final class ProviderAvatarRedirectGuard: NSObject, URLSessionTaskDelegate {
    private let originalURL: URL

    init(originalURL: URL) {
        self.originalURL = originalURL
        super.init()
    }

    // The completion-handler form, because the Xcode 27.0 compiler crashes
    // while building the async form of this Objective-C delegate method.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(
            HTTPSProviderAvatarImageLoader.isSecureRedirect(from: originalURL, to: request.url)
                ? request
                : nil
        )
    }
}

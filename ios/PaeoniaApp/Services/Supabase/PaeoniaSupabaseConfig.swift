import Foundation

enum PaeoniaSupabaseConfigError: Error, Equatable {
    case missingURL
    case invalidURL(String)
    case missingPublishableKey
    case missingRedirectURL
    case invalidRedirectURL(String)
}

struct PaeoniaSupabaseConfig: Equatable, Sendable {
    let url: URL
    let publishableKey: String
    let redirectURL: URL

    init(
        url: URL,
        publishableKey: String,
        redirectURL: URL
    ) {
        self.url = url
        self.publishableKey = publishableKey
        self.redirectURL = redirectURL
    }

    init(bundle: Bundle = .main) throws {
        let urlString = try Self.requiredString(
            forKey: "PaeoniaSupabaseURL",
            in: bundle,
            missingError: .missingURL
        )

        guard let url = URL(string: urlString), url.scheme != nil, url.host() != nil else {
            throw PaeoniaSupabaseConfigError.invalidURL(urlString)
        }

        let publishableKey = try Self.requiredString(
            forKey: "PaeoniaSupabasePublishableKey",
            in: bundle,
            missingError: .missingPublishableKey
        )

        let redirectURLString = try Self.requiredString(
            forKey: "PaeoniaAuthRedirectURL",
            in: bundle,
            missingError: .missingRedirectURL
        )

        guard let redirectURL = URL(string: redirectURLString), redirectURL.scheme != nil else {
            throw PaeoniaSupabaseConfigError.invalidRedirectURL(redirectURLString)
        }

        self.init(url: url, publishableKey: publishableKey, redirectURL: redirectURL)
    }

    private static func requiredString(
        forKey key: String,
        in bundle: Bundle,
        missingError: PaeoniaSupabaseConfigError
    ) throws -> String {
        guard
            let rawValue = bundle.object(forInfoDictionaryKey: key) as? String,
            let value = rawValue.nilIfPlaceholder?.nilIfBlank
        else {
            throw missingError
        }

        return value
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated var nilIfPlaceholder: String? {
        hasPrefix("$(") ? nil : self
    }
}

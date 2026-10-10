import Foundation

/// Calls Convex functions over the HTTP API (`/api/query`, `/api/mutation`, `/api/action`).
///
/// Arguments and results use the same JSON conventions the Supabase RPCs used:
/// snake_case keys come from each type's `CodingKeys`, and dates are ISO-8601
/// strings with fractional seconds. Reads are queries, writes are mutations, and
/// the few StoreKit calls are actions.
nonisolated final class PaeoniaConvexClient: Sendable {
    typealias TokenProvider = @Sendable () async throws -> String?

    private let deploymentURL: URL
    private let session: URLSession
    private let tokenProvider: TokenProvider

    init(
        deploymentURL: URL,
        session: URLSession = .shared,
        tokenProvider: @escaping TokenProvider
    ) {
        self.deploymentURL = deploymentURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    /// One-shot read of a Convex query function (`POST /api/query`).
    func query<Result: Decodable>(
        _ path: String,
        args: some Encodable = PaeoniaConvexNoArgs()
    ) async throws -> Result {
        try await call(kind: "query", path: path, args: args)
    }

    func query(_ path: String, args: some Encodable = PaeoniaConvexNoArgs()) async throws {
        let _: PaeoniaConvexIgnoredResult = try await call(kind: "query", path: path, args: args)
    }

    func mutation<Result: Decodable>(
        _ path: String,
        args: some Encodable = PaeoniaConvexNoArgs()
    ) async throws -> Result {
        try await call(kind: "mutation", path: path, args: args)
    }

    func mutation(_ path: String, args: some Encodable = PaeoniaConvexNoArgs()) async throws {
        let _: PaeoniaConvexIgnoredResult = try await call(kind: "mutation", path: path, args: args)
    }

    func action<Result: Decodable>(
        _ path: String,
        args: some Encodable = PaeoniaConvexNoArgs()
    ) async throws -> Result {
        try await call(kind: "action", path: path, args: args)
    }

    /// Uploads bytes to a Convex storage upload URL and returns the storage id
    /// that `media:finalize_media_upload` expects as `p_storage_id`.
    func upload(_ data: Data, contentType: String, to uploadURL: URL) async throws -> String {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (body, response) = try await session.upload(for: request, from: data)
        try Self.requireSuccessStatus(response, body: body)
        return try Self.decoder.decode(UploadResponse.self, from: body).storageId
    }

    private func call<Result: Decodable>(
        kind: String,
        path: String,
        args: some Encodable
    ) async throws -> Result {
        var request = URLRequest(url: deploymentURL.appending(path: "api/\(kind)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = try await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try Self.encoder.encode(
            RequestBody(path: path, args: args, format: "json")
        )

        let (body, response) = try await session.data(for: request)
        try Self.requireSuccessStatus(response, body: body)

        let envelope = try Self.decoder.decode(ResponseEnvelope<Result>.self, from: body)
        switch envelope.status {
        case "success":
            guard let value = envelope.value else {
                // `null` results decode only into optional or ignored result types.
                return try Self.decoder.decode(Result.self, from: Data("null".utf8))
            }
            return value
        default:
            throw PaeoniaConvexError.server(
                code: envelope.errorData?.code,
                message: envelope.errorData?.message ?? envelope.errorMessage ?? "Unknown error"
            )
        }
    }

    private static func requireSuccessStatus(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else {
            return
        }
        // Function errors arrive as a JSON envelope, which `call` turns into
        // `.server`. Anything else is a transport failure.
        if (try? decoder.decode(ResponseEnvelope<PaeoniaConvexIgnoredResult>.self, from: body)) != nil {
            return
        }
        if http.statusCode == 401 {
            throw PaeoniaConvexError.notAuthenticated
        }
        throw PaeoniaConvexError.http(
            status: http.statusCode,
            body: String(bytes: body.prefix(2_048), encoding: .utf8) ?? ""
        )
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            // The formatter truncates milliseconds, so a decoded `.123` can print as
            // `.122` after floating point error. Aim at the middle of the
            // millisecond so cursors round-trip to the exact stored timestamp.
            let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
            let centered = Date(timeIntervalSince1970: (milliseconds + 0.5) / 1_000)
            try container.encode(centered.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Convex timestamps carry milliseconds, but accept whole seconds too.
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false)) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(string)"
            )
        }
        return decoder
    }()

    private struct RequestBody<Args: Encodable>: Encodable {
        let path: String
        let args: Args
        let format: String
    }

    private struct ResponseEnvelope<Value: Decodable>: Decodable {
        let status: String
        let value: Value?
        let errorMessage: String?
        let errorData: ErrorData?
    }

    private struct ErrorData: Decodable {
        let code: String?
        let message: String?
    }

    private struct UploadResponse: Decodable {
        let storageId: String
    }
}

/// Empty argument object for functions that take no arguments.
nonisolated struct PaeoniaConvexNoArgs: Encodable, Sendable {}

/// Result type for calls whose return value is not needed.
nonisolated struct PaeoniaConvexIgnoredResult: Decodable, Sendable {
    init(from decoder: Decoder) throws {}
}

nonisolated enum PaeoniaConvexError: Error, Equatable, CustomStringConvertible {
    case notAuthenticated
    /// A function threw. `code` is the SQLSTATE-style code the backend kept
    /// from the Supabase era, and `message` is the exact backend message.
    case server(code: String?, message: String)
    case http(status: Int, body: String)

    var description: String {
        switch self {
        case .notAuthenticated:
            "PaeoniaConvexError.notAuthenticated"
        case let .server(code, message):
            "PaeoniaConvexError.server(code: \(code ?? "nil"), message: \(message))"
        case let .http(status, body):
            "PaeoniaConvexError.http(status: \(status), body: \(body))"
        }
    }
}

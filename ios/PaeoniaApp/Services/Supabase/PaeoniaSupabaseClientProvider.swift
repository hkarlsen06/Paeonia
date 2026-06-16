import Foundation
import Supabase

final class PaeoniaSupabaseClientProvider: @unchecked Sendable {
    nonisolated static let shared = PaeoniaSupabaseClientProvider()

    private let clientResult: Result<SupabaseClient, Error>

    init(config: PaeoniaSupabaseConfig? = nil) {
        clientResult = Result {
            let resolvedConfig = try config ?? PaeoniaSupabaseConfig()
            return SupabaseClient(
                supabaseURL: resolvedConfig.url,
                supabaseKey: resolvedConfig.publishableKey,
                options: SupabaseClientOptions(
                    auth: SupabaseClientOptions.AuthOptions(
                        redirectToURL: resolvedConfig.redirectURL,
                        storageKey: "paeonia-auth-session",
                        autoRefreshToken: true,
                        emitLocalSessionAsInitialSession: true
                    )
                )
            )
        }
    }

    nonisolated func client() throws -> SupabaseClient {
        try clientResult.get()
    }

    nonisolated func handle(_ url: URL) {
        guard case let .success(client) = clientResult else {
            return
        }

        client.handle(url)
    }
}

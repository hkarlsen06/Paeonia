import AppIntents
import Foundation

/// "Search Paeonia for Bergen." Opens the Search screen with the words typed in.
@AppIntent(schema: .system.searchInApp)
struct SearchPaeoniaIntent {
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        if await coupleToOpenFor() != nil {
            SiriAppContext.shared.open(.search(term: criteria.term))
        }
        return .result()
    }
}

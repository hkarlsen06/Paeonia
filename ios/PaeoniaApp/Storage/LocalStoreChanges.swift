import Foundation

/// A part of the local store that view models can watch.
nonisolated enum LocalStoreDomain: String, CaseIterable, Sendable {
    case access
    case relationshipEvents
    case locationVisibility
    case ownLocation
    case memories
    case pendingOperations
    case dailyChallenge
    case dailyChat
    case games
    case hearts
    case coupleDates
}

/// One committed write to a `LocalStoreDomain`.
nonisolated struct LocalStoreChange: Equatable, Sendable {
    let domain: LocalStoreDomain
    /// The signed-in user whose rows changed. Filter on it so a change for a
    /// previous account never reloads the current screen.
    let ownerUserID: UUID?
}

/// Tells view models that a repository write committed, so they can re-read.
///
/// Repositories call `post` after `context.save()` succeeds. View models consume
/// `changes(in:)` and re-read the store. The stream carries no row data, so a
/// consumer that misses nothing can treat each element as "reload now".
nonisolated enum LocalStoreChanges {
    static let notificationName = Notification.Name("paeonia.localStore.didChange")

    private static let domainKey = "domain"
    private static let ownerKey = "ownerUserID"

    static func post(_ domain: LocalStoreDomain, ownerUserID: UUID?) {
        var info: [String: Any] = [domainKey: domain.rawValue]
        info[ownerKey] = ownerUserID?.uuidString
        NotificationCenter.default.post(name: notificationName, object: nil, userInfo: info)
    }

    /// Yields one element per write to any of `domains`, in write order. The
    /// stream ends when the consuming task is cancelled.
    static func changes(in domains: LocalStoreDomain...) -> AsyncStream<LocalStoreChange> {
        changes(in: Set(domains))
    }

    static func changes(in domains: Set<LocalStoreDomain>) -> AsyncStream<LocalStoreChange> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: notificationName,
                object: nil,
                queue: nil
            ) { notification in
                guard let rawDomain = notification.userInfo?[domainKey] as? String,
                      let domain = LocalStoreDomain(rawValue: rawDomain),
                      domains.contains(domain)
                else {
                    return
                }
                let owner = (notification.userInfo?[ownerKey] as? String).flatMap(UUID.init(uuidString:))
                continuation.yield(LocalStoreChange(domain: domain, ownerUserID: owner))
            }
            nonisolated(unsafe) let token = observer
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(token)
            }
        }
    }
}

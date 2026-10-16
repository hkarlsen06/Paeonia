import Foundation
import Synchronization

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
    case stories
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

    /// Yields the writes to any of `domains`, oldest first. The stream ends when
    /// the consuming task is cancelled.
    ///
    /// A consumer that is busy re-reading gets one element for a burst of
    /// identical writes, not one per write. Writes to different domains or for
    /// different users are never merged, so a consumer that switches on
    /// `change.domain` still sees each domain it watches.
    static func changes(in domains: LocalStoreDomain...) -> AsyncStream<LocalStoreChange> {
        changes(in: Set(domains))
    }

    static func changes(in domains: Set<LocalStoreDomain>) -> AsyncStream<LocalStoreChange> {
        let mailbox = ChangeMailbox()
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
            mailbox.push(LocalStoreChange(domain: domain, ownerUserID: owner))
        }
        // Removes the observer when the stream is released, also if nobody iterated it.
        let subscription = ObserverSubscription(observer)
        return AsyncStream(
            unfolding: {
                _ = subscription
                return await mailbox.next()
            },
            onCancel: { mailbox.finish() }
        )
    }
}

private nonisolated final class ObserverSubscription: Sendable {
    // The token is only passed to `removeObserver`, which is thread safe.
    nonisolated(unsafe) private let token: any NSObjectProtocol

    init(_ token: any NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

/// Holds the writes a consumer has not read yet, without repeats.
private nonisolated final class ChangeMailbox: Sendable {
    private struct State {
        var pending: [LocalStoreChange] = []
        var waiter: CheckedContinuation<LocalStoreChange?, Never>?
        var isFinished = false
    }

    private enum Pickup {
        case change(LocalStoreChange)
        case finished
        case wait
    }

    private let state = Mutex(State())

    func push(_ change: LocalStoreChange) {
        let waiter = state.withLock { state -> CheckedContinuation<LocalStoreChange?, Never>? in
            guard !state.isFinished else {
                return nil
            }
            if let waiter = state.waiter {
                state.waiter = nil
                return waiter
            }
            if !state.pending.contains(change) {
                state.pending.append(change)
            }
            return nil
        }
        waiter?.resume(returning: change)
    }

    func next() async -> LocalStoreChange? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<LocalStoreChange?, Never>) in
                let pickup = state.withLock { state -> Pickup in
                    if state.isFinished {
                        return .finished
                    }
                    if !state.pending.isEmpty {
                        return .change(state.pending.removeFirst())
                    }
                    state.waiter = continuation
                    return .wait
                }
                switch pickup {
                case let .change(change):
                    continuation.resume(returning: change)
                case .finished:
                    continuation.resume(returning: nil)
                case .wait:
                    break
                }
            }
        } onCancel: {
            finish()
        }
    }

    func finish() {
        let waiter = state.withLock { state -> CheckedContinuation<LocalStoreChange?, Never>? in
            state.isFinished = true
            state.pending.removeAll()
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiter?.resume(returning: nil)
    }
}

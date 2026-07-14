import Foundation

@MainActor
final class RootPrivacyLifecycle {
    private let syncService: any PaeoniaSyncing
    private var recoveryTask: Task<Void, Never>?
    private(set) var hasPendingRetry = false

    init(syncService: any PaeoniaSyncing) {
        self.syncService = syncService
    }

    @discardableResult
    func retryPending() async -> Bool {
        let result = await syncService.retryPendingPrivacyPurges()
        hasPendingRetry = result == .recordsPendingRetry
        return result == .completed
    }

    /// Returns true only when this call completed work that was pending before
    /// the foreground transition, so Root knows to resolve access again.
    func retryPendingOnForeground() async -> Bool {
        guard hasPendingRetry else {
            return false
        }

        return await retryPending()
    }

    func record(_ result: LocalPrivacyPurgeResult) {
        hasPendingRetry = !result.isComplete
    }

    func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    func scheduleRecovery(
        onCompleted: @escaping @MainActor @Sendable () async -> Void
    ) {
        guard recoveryTask == nil else {
            return
        }

        recoveryTask = Task { [weak self] in
            defer { self?.recoveryTask = nil }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }

                guard let self else {
                    return
                }
                guard await self.retryPending() else {
                    continue
                }

                await onCompleted()
                return
            }
        }
    }
}

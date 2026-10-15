import Foundation

extension PaeoniaSyncService {
    /// Runs every stream once. The timeout covers each stream except the pending
    /// writes, whose photo and voice uploads can take longer than any fixed budget
    /// for the whole run. That stream limits each write on its own.
    func performRunWithTimeout(
        reason: SyncRequestReason,
        session: SyncSession
    ) async -> SyncRunResult {
        let pipelineID = UUID()
        let runTask = Task {
            await performRun(reason: reason, session: session)
        }
        activePipelineTasks[pipelineID] = runTask
        let result = await withTaskCancellationHandler {
            await runTask.value
        } onCancel: {
            runTask.cancel()
        }

        removeActivePipeline(pipelineID)
        return result
    }

    /// Runs `stream` and cancels it once the timeout passes, unless it is the pending
    /// writes stream.
    private func runStreamWithTimeout(
        _ stream: any SyncStream,
        _ scope: SyncStreamScope,
        _ session: SyncSession,
        _ reason: SyncRequestReason,
        _ startedAt: Date
    ) async -> StreamOutcome {
        guard stream.streamKey != .pendingOperations else {
            return await runStream(stream, scope: scope, session: session, reason: reason, startedAt: startedAt)
        }

        let streamTask = Task {
            await runStream(stream, scope: scope, session: session, reason: reason, startedAt: startedAt)
        }
        let timeoutNanoseconds = syncTimeoutNanoseconds
        let timer = Task {
            guard (try? await Task.sleep(nanoseconds: timeoutNanoseconds)) != nil else {
                return false
            }
            streamTask.cancel()
            return true
        }
        // Cancellation is a request, not proof that the task has stopped. Wait for
        // the stream to settle so a retry cannot overlap its local writes.
        let outcome = await withTaskCancellationHandler {
            await streamTask.value
        } onCancel: {
            streamTask.cancel()
            timer.cancel()
        }
        timer.cancel()
        let didTimeOut = await timer.value
        if didTimeOut, case .cancelled = outcome {
            return .timedOut
        }
        return outcome
    }

    private func removeActivePipeline(_ id: UUID) {
        activePipelineTasks[id] = nil
    }

    private func performRun(
        reason: SyncRequestReason,
        session: SyncSession
    ) async -> SyncRunResult {
        let startedAt = Date()
        var attemptedStreamCount = 0
        var completedStreamCount = 0

        func result(
            _ status: SyncRunStatus,
            failedStreamKey: SyncStreamKey? = nil,
            errorDescription: String? = nil
        ) -> SyncRunResult {
            SyncRunResult(
                status: status,
                attemptedStreamCount: attemptedStreamCount,
                completedStreamCount: completedStreamCount,
                failedStreamKey: failedStreamKey,
                errorDescription: errorDescription
            )
        }

        try? await pendingOperationStore.resetInFlight(ownerUserID: session.userID)

        for stream in streams {
            if Task.isCancelled {
                return result(.cancelled)
            }

            guard let scope = stream.scope(for: session) else {
                continue
            }

            attemptedStreamCount += 1

            let outcome = await runStreamWithTimeout(stream, scope, session, reason, startedAt)
            switch outcome {
            case .completed:
                completedStreamCount += 1
            case .cancelled:
                return result(.cancelled, failedStreamKey: stream.streamKey)
            case .timedOut:
                return result(.timedOut, failedStreamKey: stream.streamKey)
            case let .failed(errorDescription):
                return result(.failed, failedStreamKey: stream.streamKey, errorDescription: errorDescription)
            }
        }

        return result(.succeeded)
    }

    /// Syncs one stream and says how it ended. A failure is saved on the stream's
    /// sync state first.
    private func runStream(
        _ stream: any SyncStream,
        scope: SyncStreamScope,
        session: SyncSession,
        reason: SyncRequestReason,
        startedAt: Date
    ) async -> StreamOutcome {
        do {
            try await syncStream(stream, scope: scope, session: session, reason: reason, startedAt: startedAt)
            return .completed
        } catch is CancellationError {
            return .cancelled
        } catch {
            if Task.isCancelled {
                return .cancelled
            }
            let errorDescription = await recordFailure(
                error,
                session: session,
                scope: scope,
                streamKey: stream.streamKey
            )
            return .failed(errorDescription)
        }
    }

    /// Saves the failure on the stream's sync state and returns its description.
    private func recordFailure(
        _ error: any Error,
        session: SyncSession,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey
    ) async -> String {
        let errorDescription = String(describing: error)
        try? await stateStore.markFailed(
            ownerUserID: session.userID,
            scope: scope,
            streamKey: streamKey,
            errorDescription: errorDescription,
            at: Date()
        )
        return errorDescription
    }

    /// Pulls, then pushes, one stream, and records the attempt and its outcome.
    private func syncStream(
        _ stream: any SyncStream,
        scope: SyncStreamScope,
        session: SyncSession,
        reason: SyncRequestReason,
        startedAt: Date
    ) async throws {
        let streamKey = stream.streamKey
        let cursor = try await stateStore.cursor(
            ownerUserID: session.userID,
            scope: scope,
            streamKey: streamKey
        )
        try Task.checkCancellation()
        let context = SyncContext(
            session: session,
            reason: reason,
            startedAt: startedAt,
            streamCursor: cursor,
            stateStore: stateStore,
            pendingOperationStore: pendingOperationStore
        )

        try await stateStore.markAttempted(
            ownerUserID: session.userID,
            scope: scope,
            streamKey: streamKey,
            at: startedAt
        )
        try Task.checkCancellation()
        let nextCursor = try await stream.pull(context: context)
        try Task.checkCancellation()
        try await stream.push(context: context)
        try Task.checkCancellation()
        try await stateStore.markSucceeded(
            ownerUserID: session.userID,
            scope: scope,
            streamKey: streamKey,
            cursor: nextCursor,
            at: Date()
        )
    }
}

private enum StreamOutcome {
    case completed
    case cancelled
    case timedOut
    case failed(String)
}

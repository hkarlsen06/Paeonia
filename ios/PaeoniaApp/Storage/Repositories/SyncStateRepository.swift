import Foundation
import SwiftData

nonisolated struct SyncStreamScope: Equatable, Sendable {
    let kind: SyncScopeKind
    let id: UUID?

    init(kind: SyncScopeKind, id: UUID? = nil) {
        self.kind = kind
        self.id = id
    }
}

nonisolated struct SyncStateSnapshot: Equatable, Sendable {
    let ownerUserID: UUID
    let scope: SyncStreamScope
    let streamKey: SyncStreamKey
    let cursor: SyncCursor
    let lastSuccessfulSyncAt: Date?
    let lastSyncAttemptAt: Date?
    let lastSyncError: String?
}

protocol SyncStatePersisting: Actor {
    func cursor(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey
    ) async throws -> SyncCursor

    func markAttempted(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        at date: Date
    ) async throws

    func markSucceeded(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        cursor: SyncCursor?,
        at date: Date
    ) async throws

    func markFailed(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        errorDescription: String,
        at date: Date
    ) async throws

    func snapshots(ownerUserID: UUID) async throws -> [SyncStateSnapshot]
    func deleteStates(ownerUserID: UUID) async throws
}

actor SwiftDataSyncStateRepository: SyncStatePersisting {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func cursor(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey
    ) async throws -> SyncCursor {
        let context = ModelContext(container)
        let state = try fetchOrCreateState(
            ownerUserID: ownerUserID,
            scope: scope,
            streamKey: streamKey,
            in: context
        )
        return state.cursor
    }

    func markAttempted(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        at date: Date
    ) async throws {
        let context = ModelContext(container)
        let state = try fetchOrCreateState(
            ownerUserID: ownerUserID,
            scope: scope,
            streamKey: streamKey,
            in: context
        )
        state.markAttempted(at: date)
        try context.save()
    }

    func markSucceeded(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        cursor: SyncCursor?,
        at date: Date
    ) async throws {
        let context = ModelContext(container)
        let state = try fetchOrCreateState(
            ownerUserID: ownerUserID,
            scope: scope,
            streamKey: streamKey,
            in: context
        )
        state.markSucceeded(cursor: cursor, at: date)
        try context.save()
    }

    func markFailed(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        errorDescription: String,
        at date: Date
    ) async throws {
        let context = ModelContext(container)
        let state = try fetchOrCreateState(
            ownerUserID: ownerUserID,
            scope: scope,
            streamKey: streamKey,
            in: context
        )
        state.markFailed(errorDescription, at: date)
        try context.save()
    }

    func snapshots(ownerUserID: UUID) async throws -> [SyncStateSnapshot] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalSyncState>(
            predicate: #Predicate { state in
                state.ownerUserID == ownerUserID
            },
            sortBy: [
                SortDescriptor(\.streamKeyRawValue),
                SortDescriptor(\.key)
            ]
        )

        return try context.fetch(descriptor).map(Self.snapshot(from:))
    }

    func deleteStates(ownerUserID: UUID) async throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalSyncState>(
            predicate: #Predicate { state in
                state.ownerUserID == ownerUserID
            }
        )
        for state in try context.fetch(descriptor) {
            context.delete(state)
        }

        try context.save()
    }

    private func fetchOrCreateState(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        in context: ModelContext
    ) throws -> LocalSyncState {
        let key = LocalSyncState.makeKey(
            ownerUserID: ownerUserID,
            scopeKind: scope.kind,
            scopeID: scope.id,
            streamKey: streamKey
        )
        var descriptor = FetchDescriptor<LocalSyncState>(
            predicate: #Predicate { state in
                state.key == key
            }
        )
        descriptor.fetchLimit = 1

        if let existingState = try context.fetch(descriptor).first {
            return existingState
        }

        let state = LocalSyncState(
            ownerUserID: ownerUserID,
            scopeKind: scope.kind,
            scopeID: scope.id,
            streamKey: streamKey
        )
        context.insert(state)
        return state
    }

    private static func snapshot(from state: LocalSyncState) -> SyncStateSnapshot {
        SyncStateSnapshot(
            ownerUserID: state.ownerUserID,
            scope: SyncStreamScope(kind: state.scopeKind, id: state.scopeID),
            streamKey: state.streamKey,
            cursor: state.cursor,
            lastSuccessfulSyncAt: state.lastSuccessfulSyncAt,
            lastSyncAttemptAt: state.lastSyncAttemptAt,
            lastSyncError: state.lastSyncError
        )
    }
}

actor InMemorySyncStateRepository: SyncStatePersisting {
    private var states: [String: SyncStateSnapshot] = [:]

    func cursor(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey
    ) async throws -> SyncCursor {
        state(ownerUserID: ownerUserID, scope: scope, streamKey: streamKey).cursor
    }

    func markAttempted(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        at date: Date
    ) async throws {
        update(ownerUserID: ownerUserID, scope: scope, streamKey: streamKey) {
            SyncStateSnapshot(
                ownerUserID: ownerUserID,
                scope: scope,
                streamKey: streamKey,
                cursor: $0.cursor,
                lastSuccessfulSyncAt: $0.lastSuccessfulSyncAt,
                lastSyncAttemptAt: date,
                lastSyncError: $0.lastSyncError
            )
        }
    }

    func markSucceeded(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        cursor: SyncCursor?,
        at date: Date
    ) async throws {
        update(ownerUserID: ownerUserID, scope: scope, streamKey: streamKey) {
            SyncStateSnapshot(
                ownerUserID: ownerUserID,
                scope: scope,
                streamKey: streamKey,
                cursor: cursor ?? $0.cursor,
                lastSuccessfulSyncAt: date,
                lastSyncAttemptAt: date,
                lastSyncError: nil
            )
        }
    }

    func markFailed(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        errorDescription: String,
        at date: Date
    ) async throws {
        update(ownerUserID: ownerUserID, scope: scope, streamKey: streamKey) {
            SyncStateSnapshot(
                ownerUserID: ownerUserID,
                scope: scope,
                streamKey: streamKey,
                cursor: $0.cursor,
                lastSuccessfulSyncAt: $0.lastSuccessfulSyncAt,
                lastSyncAttemptAt: date,
                lastSyncError: errorDescription
            )
        }
    }

    func snapshots(ownerUserID: UUID) async throws -> [SyncStateSnapshot] {
        states.values
            .filter { $0.ownerUserID == ownerUserID }
            .sorted { $0.streamKey.rawValue < $1.streamKey.rawValue }
    }

    func deleteStates(ownerUserID: UUID) async throws {
        states = states.filter { $0.value.ownerUserID != ownerUserID }
    }

    private func state(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey
    ) -> SyncStateSnapshot {
        let key = makeKey(ownerUserID: ownerUserID, scope: scope, streamKey: streamKey)

        if let existingState = states[key] {
            return existingState
        }

        let newState = SyncStateSnapshot(
            ownerUserID: ownerUserID,
            scope: scope,
            streamKey: streamKey,
            cursor: SyncCursor(),
            lastSuccessfulSyncAt: nil,
            lastSyncAttemptAt: nil,
            lastSyncError: nil
        )
        states[key] = newState
        return newState
    }

    private func update(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey,
        transform: (SyncStateSnapshot) -> SyncStateSnapshot
    ) {
        let key = makeKey(ownerUserID: ownerUserID, scope: scope, streamKey: streamKey)
        states[key] = transform(state(ownerUserID: ownerUserID, scope: scope, streamKey: streamKey))
    }

    private func makeKey(
        ownerUserID: UUID,
        scope: SyncStreamScope,
        streamKey: SyncStreamKey
    ) -> String {
        LocalSyncState.makeKey(
            ownerUserID: ownerUserID,
            scopeKind: scope.kind,
            scopeID: scope.id,
            streamKey: streamKey
        )
    }
}

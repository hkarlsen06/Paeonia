import Foundation
import Observation

@MainActor
@Observable
final class RelationshipMilestoneViewModel {
    private(set) var startedOn: String?
    private(set) var isSaving = false
    private(set) var error: RelationshipMilestoneError?

    private let dataService: any RelationshipStartedOnDataServicing
    private let operationProvider: any PairingClientOperationProviding
    private var ownerUserID: UUID?
    private var latestServerStartedOn: String?
    private var hasPendingLocalChange = false
    private var configurationGeneration = 0
    private var localMutationGeneration = 0
    private var reconciliationGeneration = 0
    private var syncAfterLocalChange: @MainActor () async -> Void = {}

    init(
        dataService: (any RelationshipStartedOnDataServicing)? = nil,
        operationProvider: (any PairingClientOperationProviding)? = nil
    ) {
        self.dataService = dataService ?? RelationshipStartedOnDataServiceFactory.makeDefault()
        self.operationProvider = operationProvider ?? PairingClientOperationFactory.shared
    }

    func configure(ownerUserID: UUID?, serverStartedOn: String?) async {
        configurationGeneration &+= 1
        let activeConfigurationGeneration = configurationGeneration
        let priorOwnerUserID = self.ownerUserID
        if priorOwnerUserID != ownerUserID {
            // Invalidate any suspended save/configure work from the previous
            // account before it can write presentation state for this identity.
            localMutationGeneration &+= 1
            reconciliationGeneration &+= 1
            isSaving = false
            hasPendingLocalChange = false
        }

        self.ownerUserID = ownerUserID
        latestServerStartedOn = Self.validated(serverStartedOn)
        let initialLocalMutationGeneration = localMutationGeneration

        guard let ownerUserID else {
            startedOn = latestServerStartedOn
            return
        }

        do {
            let localState = try await dataService.loadStartedOn(ownerUserID: ownerUserID)
            guard self.configurationGeneration == activeConfigurationGeneration,
                  self.ownerUserID == ownerUserID,
                  self.localMutationGeneration == initialLocalMutationGeneration
            else {
                return
            }

            startedOn = Self.validated(localState.startedOn) ?? latestServerStartedOn
            hasPendingLocalChange = localState.hasPendingChange

            if localState.hasPendingChange {
                schedulePendingChangeRetry(for: ownerUserID)
            }
        } catch {
            guard self.configurationGeneration == activeConfigurationGeneration,
                  self.ownerUserID == ownerUserID,
                  self.localMutationGeneration == initialLocalMutationGeneration
            else {
                return
            }

            startedOn = latestServerStartedOn
            hasPendingLocalChange = false
        }
    }

    /// Applies a server refresh without hiding a newer local choice that is still
    /// queued. `configure` performs the pending-operation lookup after relaunch.
    func refreshServerStartedOn(_ serverStartedOn: String?) {
        latestServerStartedOn = Self.validated(serverStartedOn)
        guard !isSaving else { return }

        if hasPendingLocalChange {
            // Matching server copy is not proof that this device's durable
            // operation finished (the partner may have chosen the same date).
            // Only the pending-operation store can settle local-first state.
            if let ownerUserID {
                Task { [weak self] in
                    await self?.reconcilePendingChange(for: ownerUserID)
                }
            }
            return
        }

        startedOn = latestServerStartedOn
    }

    func setSyncAfterLocalChange(_ handler: @escaping @MainActor () async -> Void) {
        syncAfterLocalChange = handler
    }

    @discardableResult
    func save(startedOn date: Date, calendar: Calendar = .current) async -> Bool {
        guard !isSaving else { return false }
        guard let ownerUserID else {
            error = .saveFailed
            return false
        }

        let startOfSelectedDay = calendar.startOfDay(for: date)
        let startOfToday = calendar.startOfDay(for: Date())
        guard startOfSelectedDay <= startOfToday else {
            error = .futureDate
            return false
        }

        let relationshipStartDate = PairingStartDate(date: date, calendar: calendar)
        let previousStartedOn = startedOn
        let previouslyHadPendingLocalChange = hasPendingLocalChange
        localMutationGeneration &+= 1
        let activeLocalMutationGeneration = localMutationGeneration
        startedOn = relationshipStartDate.rawValue
        hasPendingLocalChange = true
        isSaving = true
        error = nil

        do {
            try await dataService.setStartedOn(
                relationshipStartDate,
                ownerUserID: ownerUserID,
                operation: operationProvider.makeOperation()
            )
            return finishSuccessfulSave(
                ownerUserID: ownerUserID,
                mutationGeneration: activeLocalMutationGeneration
            )
        } catch {
            return finishFailedSave(
                ownerUserID: ownerUserID,
                mutationGeneration: activeLocalMutationGeneration,
                previousStartedOn: previousStartedOn,
                previouslyHadPendingLocalChange: previouslyHadPendingLocalChange
            )
        }
    }

    func clearError() {
        error = nil
    }

    /// Gives a durable offline edit another ordered sync attempt when the app
    /// becomes active. This also resolves a superseded retry to the date the
    /// server confirmed, even when that server value did not change and SwiftUI
    /// therefore emitted no `onChange` callback.
    func retryPendingChangeIfNeeded() async {
        guard !isSaving, hasPendingLocalChange, let ownerUserID else { return }
        await syncAfterLocalChange()
        await reconcilePendingChange(for: ownerUserID)
    }

    private func schedulePendingChangeRetry(for ownerUserID: UUID) {
        Task { [weak self] in
            await self?.retryPendingChange(for: ownerUserID)
        }
    }

    private func retryPendingChange(for ownerUserID: UUID) async {
        guard self.ownerUserID == ownerUserID,
              !isSaving,
              hasPendingLocalChange
        else {
            return
        }
        await syncAfterLocalChange()
        await reconcilePendingChange(for: ownerUserID)
    }

    private func reconcilePendingChange(for ownerUserID: UUID) async {
        guard self.ownerUserID == ownerUserID,
              !isSaving,
              hasPendingLocalChange
        else {
            return
        }

        reconciliationGeneration &+= 1
        let activeReconciliationGeneration = reconciliationGeneration

        guard let localState = try? await dataService.loadStartedOn(ownerUserID: ownerUserID),
              self.ownerUserID == ownerUserID,
              reconciliationGeneration == activeReconciliationGeneration
        else {
            return
        }

        hasPendingLocalChange = localState.hasPendingChange
        if localState.hasPendingChange {
            startedOn = Self.validated(localState.startedOn) ?? startedOn
        } else {
            // The pending handler writes its confirmed response into the access
            // snapshot before marking the operation complete. Prefer that value;
            // fall back to the latest root snapshot if local persistence failed.
            startedOn = Self.validated(localState.startedOn) ?? latestServerStartedOn
        }
    }

    private func finishSuccessfulSave(
        ownerUserID: UUID,
        mutationGeneration: Int
    ) -> Bool {
        guard self.ownerUserID == ownerUserID,
              localMutationGeneration == mutationGeneration
        else {
            return true
        }

        isSaving = false
        schedulePendingChangeRetry(for: ownerUserID)
        return true
    }

    private func finishFailedSave(
        ownerUserID: UUID,
        mutationGeneration: Int,
        previousStartedOn: String?,
        previouslyHadPendingLocalChange: Bool
    ) -> Bool {
        guard self.ownerUserID == ownerUserID,
              localMutationGeneration == mutationGeneration
        else {
            return false
        }

        startedOn = previousStartedOn
        hasPendingLocalChange = previouslyHadPendingLocalChange
        isSaving = false
        error = .saveFailed
        return false
    }

    private static func validated(_ rawValue: String?) -> String? {
        guard let rawValue,
              let date = try? PairingStartDate(rawValue: rawValue)
        else {
            return nil
        }
        return date.rawValue
    }
}

nonisolated enum RelationshipMilestoneError: Equatable, Sendable {
    case futureDate
    case saveFailed

    var message: String {
        switch self {
        case .futureDate:
            String(localized: .homeMilestoneErrorFutureDate)
        case .saveFailed:
            String(localized: .homeMilestoneErrorSaveFailed)
        }
    }
}

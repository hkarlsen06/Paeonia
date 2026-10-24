import Foundation
import Observation

@MainActor
@Observable
final class PairingInviteViewModel: PresentationReadinessProviding {
    private(set) var invite: PairingInvite?
    private(set) var isLoading = false
    private(set) var isRevoking = false
    /// The newest problem. The view shows it in the top banner and then clears it, except
    /// for `.createFailed`, which stays so the retry card can show.
    private(set) var error: PairingInviteFlowError? {
        didSet { errorFailure = .other }
    }
    /// Why the newest problem happened, so its copy blames the connection only when
    /// the phone is offline. A problem without a thrown error counts as `.other`.
    private(set) var errorFailure = PaeoniaFailure.other
    private(set) var didCopyCode = false

    private let userID: String?
    private let pairingService: (any PairingServicing)?
    private let operationProvider: any PairingClientOperationProviding
    private let inviteStore: any PairingInviteStoring
    private let now: @MainActor () -> Date
    private var cachedInvite: PairingInvite?
    private var copyResetTask: Task<Void, Never>?

    init(
        userID: String?,
        pairingService: (any PairingServicing)? = nil,
        operationProvider: (any PairingClientOperationProviding)? = nil,
        inviteStore: (any PairingInviteStoring)? = nil,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.userID = userID
        self.pairingService = pairingService ?? (try? RemotePairingService.live())
        self.operationProvider = operationProvider ?? PairingClientOperationFactory.shared
        self.inviteStore = inviteStore ?? UserDefaultsPairingInviteStore.shared
        self.now = now

        if let userID {
            cachedInvite = self.inviteStore.loadInvite(for: userID)
        }
    }

    var isPresentationReady: Bool {
        invite != nil || error == .createFailed
    }

    /// True while something is changing the invite, so buttons wait.
    var isBusy: Bool {
        isLoading || isRevoking
    }

    func loadInviteIfNeeded() async {
        guard invite == nil, !isLoading else {
            return
        }

        if let cachedInvite {
            await validateCachedInvite(cachedInvite)
            return
        }

        await createInvite()
    }

    func createInvite() async {
        guard !isLoading, !isRevoking else {
            return
        }

        guard let userID, let pairingService else {
            error = .createFailed
            return
        }

        isLoading = true
        error = nil

        do {
            let createdInvite = try await pairingService.createInvite(
                operation: operationProvider.makeOperation(),
                expiresAt: inviteExpiryDate()
            )
            invite = createdInvite
            inviteStore.saveInvite(createdInvite, for: userID)
        } catch {
            self.error = .createFailed
            errorFailure = PaeoniaFailure(error)
        }

        isLoading = false
    }

    /// Replaces the shown code. A failure keeps the current code on screen and reports
    /// `.replaceFailed`. Only when there is no code at all does it show the retry card.
    @discardableResult
    func revokeAndCreateNewInvite() async -> Bool {
        guard !isLoading, !isRevoking else {
            return false
        }

        let existingInvite = invite
        isRevoking = true
        error = nil
        defer { isRevoking = false }

        guard let userID, let pairingService else {
            error = existingInvite == nil ? .createFailed : .replaceFailed
            return false
        }

        do {
            let createdInvite: PairingInvite
            if let existingInvite {
                createdInvite = try await pairingService.rotateInvite(
                    currentInvite: existingInvite,
                    operation: operationProvider.makeOperation(),
                    expiresAt: inviteExpiryDate()
                )
            } else {
                createdInvite = try await pairingService.createInvite(
                    operation: operationProvider.makeOperation(),
                    expiresAt: inviteExpiryDate()
                )
            }
            invite = createdInvite
            cachedInvite = nil
            inviteStore.saveInvite(createdInvite, for: userID)
            return true
        } catch {
            if existingInvite == nil {
                inviteStore.clearInvite(for: userID)
                self.error = .createFailed
            } else {
                self.error = .replaceFailed
            }
            errorFailure = PaeoniaFailure(error)
            return false
        }
    }

    /// Swaps in a fresh code when the shown one passed its 30 days while the app was away.
    /// Returns false only when a swap was needed and failed.
    func replaceInviteIfExpired() async -> Bool {
        guard let invite, invite.expiresAt <= now() else {
            return true
        }

        return await revokeAndCreateNewInvite()
    }

    func clearError() {
        error = nil
    }

    /// Call after writing the code to the pasteboard. Shows "Copied" for a moment, and a
    /// second copy restarts that moment instead of ending early.
    func noteCodeCopied() {
        didCopyCode = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else {
                return
            }

            self?.didCopyCode = false
        }
    }

    // MARK: - Invite helpers

    private func inviteExpiryDate() -> Date {
        Calendar.current.date(byAdding: .day, value: PairingInviteCode.lifetimeDays, to: now())
            ?? now().addingTimeInterval(TimeInterval(PairingInviteCode.lifetimeDays) * 24 * 60 * 60)
    }

    private func validateCachedInvite(_ cachedInvite: PairingInvite) async {
        guard let userID, let pairingService else {
            error = .createFailed
            return
        }

        isLoading = true
        error = nil

        do {
            let validation = try await pairingService.validateInvite(cachedInvite)
            if validation.status == .pending,
               let inviteID = validation.inviteID,
               let expiresAt = validation.expiresAt {
                let validatedInvite = PairingInvite(
                    id: inviteID,
                    code: cachedInvite.code,
                    joinURL: cachedInvite.joinURL,
                    expiresAt: expiresAt
                )
                invite = validatedInvite
                self.cachedInvite = nil
                inviteStore.saveInvite(validatedInvite, for: userID)
                isLoading = false
                return
            }

            self.cachedInvite = nil
            inviteStore.clearInvite(for: userID)
            isLoading = false
            await createInvite()
        } catch is CancellationError {
            isLoading = false
        } catch {
            // The check did not finish, which is not the same as the server saying the
            // code is dead. A code that has not expired is still the best one to show.
            if cachedInvite.expiresAt > now() {
                invite = cachedInvite
                self.cachedInvite = nil
            } else {
                self.error = .createFailed
                errorFailure = PaeoniaFailure(error)
            }
            isLoading = false
        }
    }
}

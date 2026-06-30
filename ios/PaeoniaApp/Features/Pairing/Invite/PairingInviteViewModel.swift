import Foundation
import Observation

@MainActor
@Observable
final class PairingInviteViewModel: PresentationReadinessProviding {
    private(set) var invite: PairingInvite?
    private(set) var isLoading = false
    private(set) var isRevoking = false
    private(set) var error: PairingInviteFlowError?

    private let userID: String?
    private let pairingService: (any PairingServicing)?
    private let operationProvider: any PairingClientOperationProviding
    private let inviteStore: any PairingInviteStoring
    private let now: @MainActor () -> Date

    init(
        userID: String?,
        pairingService: (any PairingServicing)? = nil,
        operationProvider: (any PairingClientOperationProviding)? = nil,
        inviteStore: (any PairingInviteStoring)? = nil,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.userID = userID
        self.pairingService = pairingService ?? (try? SupabasePairingService.live())
        self.operationProvider = operationProvider ?? PairingClientOperationFactory.shared
        self.inviteStore = inviteStore ?? UserDefaultsPairingInviteStore.shared
        self.now = now

        if let userID {
            invite = self.inviteStore.loadInvite(for: userID)
        }
    }

    var isPresentationReady: Bool {
        invite != nil || error != nil
    }

    func loadInviteIfNeeded() async {
        guard invite == nil, !isLoading else {
            return
        }

        await createInvite()
    }

    func createInvite() async {
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
        }

        isLoading = false
    }

    @discardableResult
    func revokeAndCreateNewInvite() async -> Bool {
        guard !isLoading, !isRevoking else {
            return false
        }

        guard let userID else {
            error = .createFailed
            return false
        }

        let existingInvite = invite
        isRevoking = true
        error = nil

        if let invite, let pairingService {
            _ = try? await pairingService.revokeInvite(id: invite.id)
        }

        guard let pairingService else {
            isRevoking = false
            if existingInvite == nil {
                invite = nil
                inviteStore.clearInvite(for: userID)
                error = .createFailed
            }
            return false
        }

        do {
            let createdInvite = try await pairingService.createInvite(
                operation: operationProvider.makeOperation(),
                expiresAt: inviteExpiryDate()
            )
            invite = createdInvite
            inviteStore.saveInvite(createdInvite, for: userID)
            isRevoking = false
            return true
        } catch {
            invite = existingInvite
            if existingInvite == nil {
                inviteStore.clearInvite(for: userID)
                self.error = .createFailed
            }
            isRevoking = false
            return false
        }
    }

    func clearError() {
        error = nil
    }

    private func inviteExpiryDate() -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: now())
            ?? now().addingTimeInterval(7 * 24 * 60 * 60)
    }
}

enum PairingInviteFlowError: Equatable {
    case createFailed

    var message: LocalizedStringResource {
        switch self {
        case .createFailed:
            .pairingInviteErrorMessage
        }
    }
}

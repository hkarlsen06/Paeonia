import Foundation
import Observation

@MainActor
@Observable
final class PairingInviteViewModel {
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

    func revokeAndCreateNewInvite() async {
        guard !isLoading, !isRevoking else {
            return
        }

        guard let userID else {
            error = .createFailed
            return
        }

        isRevoking = true
        error = nil

        if let invite, let pairingService {
            _ = try? await pairingService.revokeInvite(id: invite.id)
        }

        guard let pairingService else {
            invite = nil
            inviteStore.clearInvite(for: userID)
            error = .createFailed
            isRevoking = false
            return
        }

        do {
            let createdInvite = try await pairingService.createInvite(
                operation: operationProvider.makeOperation(),
                expiresAt: inviteExpiryDate()
            )
            invite = createdInvite
            inviteStore.saveInvite(createdInvite, for: userID)
        } catch {
            invite = nil
            inviteStore.clearInvite(for: userID)
            self.error = .createFailed
        }

        isRevoking = false
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

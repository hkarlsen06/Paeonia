import Foundation
import Observation

/// Checks a partner's code and joins it. The root owns one, so a code typed on the
/// paywall or the invite screen is checked once, and the join screen opens with the
/// inviter already known.
@Observable
final class PairingJoinViewModel {
    /// Who the checked code belongs to.
    private(set) var invitePreview: PairingInvitePreview?
    /// The normalized code `invitePreview` belongs to.
    private(set) var checkedCode: String?
    private(set) var isChecking = false
    private(set) var isAccepting = false
    /// This person asked to bring back what the two had, and the inviter has not answered yet.
    /// Either answer pairs them, and the root then leaves this screen.
    private(set) var isWaitingForPartner = false
    /// The newest problem. The caller decides whether it goes to the banner.
    private(set) var lastError: PairingJoinError?

    /// The user the preview was checked for. A different user checks again.
    private var checkedUserID: String?
    /// An accept whose answer never arrived, so it may have paired the couple.
    /// Retrying the same code reuses its operation, and the server replays the
    /// stored result instead of failing because the couple now exists. The retry
    /// also skips the preview, which would now report the used invite as gone.
    private var unconfirmedAccept: UnconfirmedJoin?

    private let pairingService: (any PairingServicing)?
    private let operationProvider: any SyncClientOperationProviding

    init(
        pairingService: (any PairingServicing)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.pairingService = pairingService ?? (try? RemotePairingService.live())
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
    }

    var isBusy: Bool {
        isChecking || isAccepting
    }

    /// The preview for `code`, or nil while that code has not been checked.
    func preview(for code: String?) -> PairingInvitePreview? {
        guard let code, let checkedCode,
              (try? PairingInviteCode.normalized(code)) == checkedCode
        else {
            return nil
        }

        return invitePreview
    }

    /// The last check could not finish, and trying again may work.
    var checkFailure: PaeoniaFailure? {
        if case let .checkFailed(failure) = lastError {
            return failure
        }
        return nil
    }

    /// Looks up who a code belongs to without joining. A failed check keeps the
    /// earlier preview, so the join screen under the code sheet stays as it was.
    func checkCode(_ codeInput: String, currentUserID: String?) async -> Bool {
        guard !isBusy else {
            return false
        }

        guard let code = try? PairingInviteCode.normalized(codeInput) else {
            return fail(.invalid)
        }

        lastError = nil
        if let known = knownPreview(for: code, userID: currentUserID) {
            show(known, code: code, userID: currentUserID)
            return true
        }

        guard let pairingService else {
            return fail(.checkFailed(.other))
        }

        isChecking = true
        defer { isChecking = false }

        do {
            guard let preview = try await pairingService.previewInvite(codeInput: code) else {
                return fail(.notFound)
            }

            if let currentUserID, AuthUserIdentity.matches(currentUserID, preview.inviterUserID.uuidString) {
                return fail(.ownCode)
            }

            show(preview, code: code, userID: currentUserID)
            return true
        } catch is CancellationError {
            return false
        } catch {
            return fail(.checkFailed(PaeoniaFailure(error)))
        }
    }

    /// Joins `code` only when `checkCode` found it, so nobody joins a code without
    /// seeing who it belongs to. The preview stays after a join, so the screen keeps
    /// showing it while the app moves on. With `restore`, it asks the inviter to bring
    /// back what the two had, and true then means the question was sent and
    /// `isWaitingForPartner` is set.
    func acceptCheckedCode(_ code: String?, restore: Bool = false) async -> Bool {
        guard !isBusy, let pairingService, let invitePreview, let checkedCode,
              preview(for: code) != nil
        else {
            return false
        }

        isAccepting = true
        lastError = nil
        defer { isAccepting = false }

        let attempt = joinAttempt(code: checkedCode, restore: restore, preview: invitePreview)
        let operation = attempt.operation

        do {
            let result = try await pairingService.acceptInvite(
                codeInput: checkedCode,
                operation: operation,
                startedOn: nil,
                restore: restore
            )
            unconfirmedAccept = nil
            isWaitingForPartner = result == .waitingForPartner
            return true
        } catch let error as PaeoniaConvexError {
            // The server answered, so nothing was saved and the next try starts
            // fresh. Only a lost answer leaves the outcome unknown.
            if case let .server(_, message) = error {
                unconfirmedAccept = nil
                if Self.inviteIsGone(message) {
                    clearCheckedCode()
                    return fail(.notFound)
                }
            } else {
                unconfirmedAccept = attempt
            }
            return fail(.joinFailed(PaeoniaFailure(error)))
        } catch is CancellationError {
            unconfirmedAccept = attempt
            return false
        } catch {
            unconfirmedAccept = attempt
            return fail(.joinFailed(PaeoniaFailure(error)))
        }
    }

    /// The join to send. It reuses the operation of an earlier join of the same code and
    /// choice whose answer never arrived, so the server replays that result.
    private func joinAttempt(code: String, restore: Bool, preview: PairingInvitePreview) -> UnconfirmedJoin {
        let operation = unconfirmedAccept
            .flatMap { $0.matches(code: code, userID: checkedUserID, restore: restore) ? $0.operation : nil }
            ?? operationProvider.makeOperation()
        return UnconfirmedJoin(
            code: code, userID: checkedUserID, restore: restore, preview: preview, operation: operation
        )
    }

    /// Forgets the checked code. An unconfirmed join is kept, so entering the same
    /// code again still replays it.
    func clearCheckedCode() {
        invitePreview = nil
        checkedCode = nil
        checkedUserID = nil
        lastError = nil
        isWaitingForPartner = false
    }

    /// The server's answers for an invite that was used, ran out, was replaced, or
    /// can no longer be joined since the preview. Trying again cannot help.
    private static func inviteIsGone(_ message: String) -> Bool {
        [
            "pairing invite is not available",
            "pairing invite is not pending",
            "pairing invite is expired",
            "pairing is blocked for this pair",
            "one of the users already has an active couple",
        ].contains { message.contains($0) }
    }

    /// A preview this user already has for `code`, from an earlier check or from a
    /// join whose answer never arrived.
    private func knownPreview(for code: String, userID: String?) -> PairingInvitePreview? {
        if checkedCode == code, checkedUserID == userID, let invitePreview {
            return invitePreview
        }

        if let unconfirmedAccept, unconfirmedAccept.code == code, unconfirmedAccept.userID == userID {
            return unconfirmedAccept.preview
        }

        return nil
    }

    private func show(_ preview: PairingInvitePreview, code: String, userID: String?) {
        invitePreview = preview
        checkedCode = code
        checkedUserID = userID
        isWaitingForPartner = preview.restoreRequested
    }

    private func fail(_ error: PairingJoinError) -> Bool {
        lastError = error
        return false
    }
}

private struct UnconfirmedJoin {
    let code: String
    let userID: String?
    /// The server hashes the choice with the operation, so the other choice needs a new one.
    let restore: Bool
    let preview: PairingInvitePreview
    let operation: PairingClientOperation

    func matches(code: String, userID: String?, restore: Bool) -> Bool {
        self.code == code && self.userID == userID && self.restore == restore
    }
}

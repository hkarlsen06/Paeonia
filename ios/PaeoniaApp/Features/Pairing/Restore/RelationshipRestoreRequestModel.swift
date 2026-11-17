import Foundation
import Observation

/// Sends the inviter's answer to a former partner who asked to bring back what the
/// two had. Either answer pairs them: "Bring it back" opens the old couple while the
/// server still can, and "Start fresh" makes a new one.
@Observable
final class RelationshipRestoreRequestModel {
    /// The answer on its way: true for bring it back, false for start fresh.
    private(set) var sendingAnswer: Bool?

    private let service: (any RelationshipRestoreAnswering)?
    private let operationProvider: any SyncClientOperationProviding

    init(
        service: (any RelationshipRestoreAnswering)? = nil,
        operationProvider: (any SyncClientOperationProviding)? = nil
    ) {
        self.service = service ?? (try? RemotePairingService.live())
        self.operationProvider = operationProvider ?? SyncClientOperationFactory.shared
    }

    enum Outcome: Equatable {
        /// The two are paired. `tooLate` means they asked to bring it back, but the
        /// time had run out, so they start fresh.
        case paired(tooLate: Bool)
        /// The question no longer stands, so nobody was paired.
        case requestGone
        case failed(PaeoniaFailure)
    }

    func answer(_ request: RemoteRestoreRequest, restore: Bool) async -> Outcome? {
        guard sendingAnswer == nil else {
            return nil
        }
        guard let service else {
            return .failed(.other)
        }

        sendingAnswer = restore
        defer { sendingAnswer = nil }
        do {
            let answer = try await service.answerRestore(
                inviteID: request.inviteID,
                restore: restore,
                operation: operationProvider.makeOperation()
            )
            guard answer.coupleID != nil else {
                return .requestGone
            }
            return .paired(tooLate: restore && !answer.restored)
        } catch is CancellationError {
            return nil
        } catch {
            return .failed(PaeoniaFailure(error))
        }
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class PrivacySafetyViewModel {
    enum Notice: Equatable {
        case loadFailed
        case requestSubmitted(PrivacyRequestKind)
        case requestAlreadyActive(PrivacyRequestKind)
        case requestFailed(PaeoniaFailure)
        case correctionDetailsRequired
    }

    private let service: (any PrivacySafetyServicing)?

    private(set) var requests = [PrivacyRequest]()
    private(set) var isLoading = false
    /// True once the first load or live update has finished, whether or not it
    /// worked. Until then the screen cannot tell "no requests" from "not loaded".
    private(set) var hasLoaded = false
    private(set) var submittingRequestKinds = Set<PrivacyRequestKind>()
    private(set) var notice: Notice?

    init(service: (any PrivacySafetyServicing)? = PrivacySafetyServiceFactory.makeDefault()) {
        self.service = service
    }

    func load() async {
        guard !isLoading else {
            return
        }
        guard let service else {
            notice = .loadFailed
            hasLoaded = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            requests = try await service.loadPrivacyRequests()
            hasLoaded = true
        } catch {
            // A cancelled `.task` or refresh is not a failure. URLSession reports it
            // as `URLError.cancelled`, not `CancellationError`.
            guard !Task.isCancelled, !error.isCancellation else {
                return
            }
            notice = .loadFailed
            hasLoaded = true
        }
    }

    /// Applies status changes as the server reports them. Runs until the screen's
    /// task is cancelled.
    func observe() async {
        guard let service else {
            return
        }
        for await latest in service.privacyRequestUpdates() {
            requests = latest
            hasLoaded = true
        }
    }

    @discardableResult
    func submitRequest(kind: PrivacyRequestKind, requesterNote: String? = nil) async -> Bool {
        if kind == .correction, !Self.hasText(requesterNote) {
            notice = .correctionDetailsRequired
            return false
        }

        guard !submittingRequestKinds.contains(kind), let service else {
            if service == nil {
                notice = .requestFailed(.other)
            }
            return false
        }

        submittingRequestKinds.insert(kind)
        defer { submittingRequestKinds.remove(kind) }

        do {
            let outcome = try await service.submitPrivacyRequest(
                kind: kind,
                requesterNote: requesterNote
            )
            upsert(outcome.request)

            switch outcome {
            case .created:
                notice = .requestSubmitted(kind)
            case .alreadyActive:
                notice = .requestAlreadyActive(kind)
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            notice = .requestFailed(PaeoniaFailure(error))
            return false
        }
    }

    func latestRequest(for kind: PrivacyRequestKind) -> PrivacyRequest? {
        requests
            .filter { $0.kind == kind }
            .max { $0.requestedAt < $1.requestedAt }
    }

    func isSubmitting(_ kind: PrivacyRequestKind) -> Bool {
        submittingRequestKinds.contains(kind)
    }

    func canSubmitCorrection(details: String) -> Bool {
        !isSubmitting(.correction) && Self.hasText(details)
    }

    func dismissNotice() {
        notice = nil
    }

    private static func hasText(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func upsert(_ request: PrivacyRequest) {
        requests.removeAll { $0.id == request.id }
        requests.append(request)
        requests.sort { $0.requestedAt > $1.requestedAt }
    }
}

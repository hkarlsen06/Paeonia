import Foundation
import Observation

@MainActor
@Observable
final class PrivacySafetyViewModel {
    enum Notice: Equatable {
        case loadFailed
        case requestSubmitted(PrivacyRequestKind)
        case requestAlreadyActive(PrivacyRequestKind)
        case requestFailed
        case correctionDetailsRequired
    }

    private let service: (any PrivacySafetyServicing)?

    private(set) var requests = [PrivacyRequest]()
    private(set) var isLoading = false
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
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            requests = try await service.loadPrivacyRequests()
        } catch is CancellationError {
            return
        } catch {
            notice = .loadFailed
        }
    }

    @discardableResult
    func submitRequest(kind: PrivacyRequestKind, requesterNote: String? = nil) async -> Bool {
        if kind == .correction {
            let details = requesterNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !details.isEmpty else {
                notice = .correctionDetailsRequired
                return false
            }
        }

        guard !submittingRequestKinds.contains(kind), let service else {
            if service == nil {
                notice = .requestFailed
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
            notice = .requestFailed
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

    func dismissNotice() {
        notice = nil
    }

    private func upsert(_ request: PrivacyRequest) {
        requests.removeAll { $0.id == request.id }
        requests.append(request)
        requests.sort { $0.requestedAt > $1.requestedAt }
    }
}

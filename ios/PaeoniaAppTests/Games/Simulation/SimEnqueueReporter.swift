import Foundation
@testable import PaeoniaApp

/// Writes each queued move to the log with what the screen showed at that moment.
@MainActor
final class SimEnqueueReporter {
    private weak var phone: SimPhone?

    init(phone: SimPhone) {
        self.phone = phone
    }

    func report(_ kind: SyncPendingOperationKind, round: UUID?) {
        guard let phone else { return }
        let model = phone.viewModel
        let screen = model.map { "\($0.phase)" } ?? "no app"
        let shown = model?.round?.id.uuidString.prefix(6) ?? "-"
        let sent = model?.round?.isDrawingSent ?? false
        let drawings = model?.pending.drawings.count ?? -1
        phone.log.add(
            "\(phone.name) queued \(kind.rawValue) for \(round?.uuidString.prefix(6) ?? "-") "
                + "[\(screen) round \(shown) sent \(sent) queued drawings \(drawings)]"
        )
    }
}

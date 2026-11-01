import Foundation

extension WidgetCanvasService {
    /// Attach the server identity to the exact local publication. Rendering and
    /// attribution stay intact, including description corrections made meanwhile.
    func acceptPublication(_ ticket: WidgetCanvasPublicationTicket, revisionID: UUID) async throws {
        try Task.checkCancellation()
        try checkPublicationTicket(ticket)
        guard let appGroupContainerURL else { return }
        let changed = try WidgetSharePayload.updateFile(in: appGroupContainerURL) { payload in
            try Task.checkCancellation()
            try checkPublicationTicket(ticket)
            guard !payload.isRedacted, payload.privacyMode == .normal,
                  payload.localPublicationID == ticket.publicationID else { return }
            payload.revisionID = revisionID.uuidString.lowercased()
        }
        guard changed else { return }
        await reloader.reloadWidget()
        try checkPublicationTicket(ticket)
        await MainActor.run {
            NotificationCenter.default.post(name: .paeoniaWidgetCanvasDidUpdate, object: nil)
        }
        try checkPublicationTicket(ticket)
    }
}

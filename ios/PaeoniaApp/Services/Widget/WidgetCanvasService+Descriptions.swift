import Foundation

extension WidgetCanvasService {
    /// Text-only edits keep the exact revision, drawing bytes, previews, author and creation time.
    /// A server version orders same-revision reads. A pending operation protects offline authorship.
    func updateDescription(_ update: WidgetDrawingDescriptionUpdate, revisionID: UUID,
                           privacyToken: LocalPrivacyWriteGuard.Token) async throws {
        guard !Task.isCancelled, LocalPrivacyWriteGuard.shared.isCurrent(privacyToken),
              let appGroupContainerURL else { return }
        let changed = try WidgetSharePayload.updateFile(in: appGroupContainerURL) { payload in
            guard LocalPrivacyWriteGuard.shared.isCurrent(privacyToken), !Task.isCancelled,
                  !payload.isRedacted, payload.privacyMode == .normal,
                  payload.revisionID.lowercased() == revisionID.uuidString.lowercased() else { return }
            payload.applyDescription(update)
        }
        guard changed else { return }
        await reloader.reloadWidget()
        await MainActor.run {
            NotificationCenter.default.post(name: .paeoniaWidgetCanvasDidUpdate, object: nil)
        }
    }

}

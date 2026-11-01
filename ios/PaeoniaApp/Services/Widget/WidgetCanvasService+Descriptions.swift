import Foundation
#if DEBUG
import OSLog
#endif

extension WidgetCanvasService {
    /// Text-only edits keep the exact revision, drawing bytes, previews, author and creation time.
    /// A server version orders same-revision reads. A pending operation protects offline authorship.
    func updateDescription(_ update: WidgetDrawingDescriptionUpdate, revisionID: UUID,
                           privacyToken: LocalPrivacyWriteGuard.Token) async {
        guard !Task.isCancelled, LocalPrivacyWriteGuard.shared.isCurrent(privacyToken),
              let appGroupContainerURL else { return }
        let changed: Bool
        do {
            changed = try WidgetSharePayload.updateFile(in: appGroupContainerURL) { payload in
                guard LocalPrivacyWriteGuard.shared.isCurrent(privacyToken), !Task.isCancelled,
                      !payload.isRedacted, payload.privacyMode == .normal,
                      payload.revisionID.lowercased() == revisionID.uuidString.lowercased() else { return }
                payload.applyDescription(update)
            }
        } catch {
            #if DEBUG
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app", category: "Widget")
            logger.error("Could not update drawing description: \(String(describing: error))")
            #endif
            return
        }
        guard changed else { return }
        await reloader.reloadWidget()
        await MainActor.run {
            NotificationCenter.default.post(name: .paeoniaWidgetCanvasDidUpdate, object: nil)
        }
    }

}

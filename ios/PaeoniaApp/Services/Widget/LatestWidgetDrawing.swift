import Foundation
import Observation

/// What a screen needs to put a reaction on the drawing it shows.
struct WidgetDrawingReactionTarget: Equatable {
    let target: ReactionTarget
    /// The partner drew it, so the user may react. For the user's own drawing the screen only
    /// shows what the partner reacted with.
    let isFromPartner: Bool
}

/// The couple's newest drawing on the server and who drew it, as the live canvas feed last saw
/// it. The files the widget reads carry no author id, and a drawing the user saved on this phone
/// carries an id that only this phone knows, so a reaction needs the server's answer.
@MainActor
@Observable
final class LatestWidgetDrawing {
    static let shared = LatestWidgetDrawing()

    private(set) var revisionID: UUID?
    private(set) var authorUserID: UUID?

    func record(revisionID: UUID?, authorUserID: UUID?) {
        self.revisionID = revisionID
        self.authorUserID = authorUserID
    }

    func clear() {
        record(revisionID: nil, authorUserID: nil)
    }

    /// The target for a screen that shows the drawing `shownRevisionID`, or nil when that is not
    /// the newest drawing on the server (the phone has not caught up yet) or nobody knows it yet.
    /// The user's own newest drawing needs no check, because this phone shows what the user saved.
    func reactionTarget(showing shownRevisionID: String?, currentUserID: UUID?) -> WidgetDrawingReactionTarget? {
        guard let revisionID, let authorUserID else { return nil }
        let target = ReactionTarget.widgetDrawing(revisionID)
        if authorUserID == currentUserID {
            return WidgetDrawingReactionTarget(target: target, isFromPartner: false)
        }
        guard shownRevisionID?.lowercased() == revisionID.uuidString.lowercased() else { return nil }
        return WidgetDrawingReactionTarget(target: target, isFromPartner: true)
    }
}

import SwiftUI

/// The reactions on the newest drawing, for a screen that shows it: what the partner reacted
/// with, and a button for the user's own reaction when the partner drew it. Nothing shows until
/// the phone knows the drawing on screen is the newest one on the server.
struct WidgetDrawingReactionControl: View {
    enum Part {
        case badge
        case button
        case both
    }

    /// The revision id of the drawing the screen shows, as the saved payload or the sync names it.
    let shownRevisionID: String?
    var part: Part = .both
    var buttonStyle: ReactionPickerButton.Style = .floating

    @Environment(ReactionStore.self) private var store: ReactionStore?

    var body: some View {
        if let store, let reaction = LatestWidgetDrawing.shared.reactionTarget(
            showing: shownRevisionID,
            currentUserID: store.participants.currentUserID
        ) {
            HStack(spacing: PaeoniaSpacing.space4) {
                if part != .button {
                    StoredReactionBadge(target: reaction.target)
                }
                if part != .badge, reaction.isFromPartner {
                    ReactionPickerButton(target: reaction.target, style: buttonStyle)
                }
            }
        }
    }
}

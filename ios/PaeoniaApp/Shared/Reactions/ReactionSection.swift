import SwiftUI

/// The reactions on a whole screen's subject: the emoji row for the user, and what the
/// partner reacted with. Where the user made the subject and cannot react to it, `canReact`
/// is false and only the partner's reaction shows.
struct ReactionSection: View {
    let target: ReactionTarget
    var canReact = true
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: PaeoniaSpacing.space8) {
            if canReact {
                ReactionPickerRow(target: target)
            }
            PartnerReactionLine(target: target)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

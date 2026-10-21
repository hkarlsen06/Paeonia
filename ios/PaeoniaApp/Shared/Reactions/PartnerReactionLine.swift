import SwiftUI

/// "Robin reacted ❤️", for something the user made or shared. Nothing until the partner reacts,
/// and nothing where no `ReactionStore` is in the environment.
struct PartnerReactionLine: View {
    let target: ReactionTarget

    @Environment(ReactionStore.self) private var store: ReactionStore?

    var body: some View {
        if let store, let emoji = store.partnerReaction(on: target) {
            Text(.reactionsPartner(store.participants.partnerName, emoji))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space8)
                .glassEffect(.regular, in: Capsule())
                .animation(PaeoniaMotion.cardReveal, value: emoji)
        }
    }
}

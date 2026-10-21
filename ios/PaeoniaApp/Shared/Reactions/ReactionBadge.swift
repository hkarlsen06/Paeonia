import SwiftUI

/// The emoji reactions on something, in a small capsule. The same emoji from both people
/// shows once with a 2. It takes no taps, so the thing under it keeps them.
struct ReactionBadge: View {
    let reactions: [EmojiReaction]
    let participants: ReactionParticipants

    var body: some View {
        HStack(spacing: 2) {
            ForEach(emojiCounts, id: \.emoji) { item in
                Text(verbatim: item.emoji)
                    .font(PaeoniaTypography.body)
                    .lineLimit(1)
                    .fixedSize()
                if item.count > 1 {
                    Text(item.count, format: .number)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextSecondary)
                }
            }
        }
        .padding(.horizontal, PaeoniaSpacing.space8)
        .padding(.vertical, 2)
        .background(.paeoniaSurfaceSecondary, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.paeoniaBackgroundPrimary, lineWidth: 2))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }

    private var emojiCounts: [(emoji: String, count: Int)] {
        var counts: [(emoji: String, count: Int)] = []
        for reaction in reactions {
            if let index = counts.firstIndex(where: { $0.emoji == reaction.emoji }) {
                counts[index].count += 1
            } else {
                counts.append((reaction.emoji, 1))
            }
        }
        return counts
    }

    private var label: String {
        reactions.map { reaction in
            reaction.userID == participants.currentUserID
                ? String(localized: .reactionsYou(reaction.emoji))
                : String(localized: .reactionsPartner(participants.partnerName, reaction.emoji))
        }.joined(separator: ", ")
    }
}

/// The reactions on `target` from `ReactionStore`, as a `ReactionBadge`. Nothing when there
/// are none, and nothing where no store is in the environment, such as a preview.
struct StoredReactionBadge: View {
    let target: ReactionTarget
    @Environment(ReactionStore.self) private var store: ReactionStore?

    var body: some View {
        if let store {
            let reactions = store.reactions(on: target)
            if !reactions.isEmpty {
                ReactionBadge(reactions: reactions, participants: store.participants)
            }
        }
    }
}

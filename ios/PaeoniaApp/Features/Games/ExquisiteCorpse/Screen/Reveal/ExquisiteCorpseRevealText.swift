import SwiftUI

/// "Meet your creature" with "Creature 12" under it.
struct ExquisiteCorpseRevealTitle: View {
    let number: Int

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(.exquisiteCorpseRevealTitle)
                .font(PaeoniaTypography.heroTitle)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(.exquisiteCorpseRevealNumber(number))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("corpse.reveal.title")
    }
}

/// One compact contribution label per drawer.
struct ExquisiteCorpseRevealCredits: View {
    let parts: [ExquisiteCorpseRevealContent.Part]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: PaeoniaSpacing.space24) {
                    rows
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                rows
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rows: some View {
        ForEach(credits, id: \.first.kind) { credit in
            HStack(spacing: PaeoniaSpacing.space8) {
                GameAvatar(player: credit.first.drawer, isMe: credit.first.drawerIsMe, size: 24)
                Text(credit.label)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private struct Credit {
        let first: ExquisiteCorpseRevealContent.Part
        let label: LocalizedStringResource
    }

    private var credits: [Credit] {
        let head = parts.first { $0.kind == .head }
        let legs = parts.first { $0.kind == .legs }
        let combinesHeadAndLegs = head != nil && legs != nil && head?.drawerIsMe == legs?.drawerIsMe
        return parts.compactMap { part in
            if combinesHeadAndLegs, part.kind == .legs { return nil }
            if combinesHeadAndLegs, part.kind == .head {
                return Credit(
                    first: part,
                    label: .exquisiteCorpseRevealPartsHeadAndLegs
                )
            }
            let label: LocalizedStringResource = switch part.kind {
            case .head: .exquisiteCorpseRevealPartsHead
            case .body: .exquisiteCorpseRevealPartsBody
            case .legs: .exquisiteCorpseRevealPartsLegs
            }
            return Credit(first: part, label: label)
        }
    }
}

/// Under the part that plays: the drawer's avatar, "Head by Robin" and, quieter,
/// the idea the drawer had.
struct ExquisiteCorpseRevealCaption: View {
    let part: ExquisiteCorpseRevealContent.Part

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space4))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space8))
        layout {
            GameAvatar(player: part.drawer, isMe: part.drawerIsMe, size: Self.avatarSize)
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .center : .leading, spacing: 0) {
                Text(part.credit)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                if let idea = part.idea {
                    Text(idea)
                        .font(PaeoniaTypography.body)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .center : .leading)
        }
        .padding(.horizontal, PaeoniaSpacing.space8)
        .accessibilityHidden(true)
    }

    private static let avatarSize: CGFloat = 24
}

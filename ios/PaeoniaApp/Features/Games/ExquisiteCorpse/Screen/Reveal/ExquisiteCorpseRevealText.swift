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

/// One row for each part: the drawer's avatar and "Head by Robin · a grandma".
/// At accessibility text sizes the avatar sits above the text.
struct ExquisiteCorpseRevealCredits: View {
    let parts: [ExquisiteCorpseRevealContent.Part]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            ForEach(parts) { part in
                row(part)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ part: ExquisiteCorpseRevealContent.Part) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space4))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space8))
        return layout {
            GameAvatar(player: part.drawer, isMe: part.drawerIsMe, size: Self.avatarSize)
                .accessibilityHidden(true)
            line(part)
                .font(PaeoniaTypography.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The credit in the main text color and the idea after a dot in the quiet one.
    private func line(_ part: ExquisiteCorpseRevealContent.Part) -> Text {
        var text = AttributedString(part.credit)
        text.foregroundColor = .paeoniaTextPrimary
        if let idea = part.idea {
            var tail = AttributedString(" · \(idea)")
            tail.foregroundColor = .paeoniaTextSecondary
            text += tail
        }
        return Text(text)
    }

    private static let avatarSize: CGFloat = 24
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

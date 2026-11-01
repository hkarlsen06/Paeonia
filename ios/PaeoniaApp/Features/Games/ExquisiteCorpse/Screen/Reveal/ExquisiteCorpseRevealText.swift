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

/// The head and legs share one credit when the same person drew both.
/// At accessibility text sizes the avatar sits above the text.
struct ExquisiteCorpseRevealCredits: View {
    let parts: [ExquisiteCorpseRevealContent.Part]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            ForEach(credits, id: \.first.kind) { credit in
                row(credit.first, text: credit.text)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var credits: [(first: ExquisiteCorpseRevealContent.Part, text: Text)] {
        let head = parts.first { $0.kind == .head }
        let legs = parts.first { $0.kind == .legs }
        let combinesHeadAndLegs = head != nil && legs != nil && head?.drawerIsMe == legs?.drawerIsMe
        return parts.compactMap { part in
            if combinesHeadAndLegs, part.kind == .legs { return nil }
            if combinesHeadAndLegs, part.kind == .head, let legs {
                let title = String(localized: .exquisiteCorpseRevealCreditHeadAndLegs(part.drawerName))
                return (part, line(title, ideas: [part.idea, legs.idea].compactMap { $0 }))
            }
            return (part, line(part.credit, ideas: [part.idea].compactMap { $0 }))
        }
    }

    private func row(_ part: ExquisiteCorpseRevealContent.Part, text: Text) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space4))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space8))
        return layout {
            GameAvatar(player: part.drawer, isMe: part.drawerIsMe, size: Self.avatarSize)
                .accessibilityHidden(true)
            text
                .font(PaeoniaTypography.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The credit in the main text color and the idea after a dot in the quiet one.
    private func line(_ credit: String, ideas: [String]) -> Text {
        var text = AttributedString(credit)
        text.foregroundColor = .paeoniaTextPrimary
        for idea in ideas {
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

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
    @AccessibilityPresentation(.media) private var showsMedia

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            creditLayout
            ForEach(parts) { part in
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    // Heads the description under it, which shows only with descriptions on.
                    if showsMedia {
                        Text(partLabel(part.kind))
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityValue(Text(part.drawing.map {
                                DrawingGeometryDescription.text($0, side: GameCanvas.canonicalSide)
                            } ?? ""))
                    }
                    MediaAlternativeReadout(text: part.accessibilityText, isVoice: false, isDrawing: true,
                        editingTarget: part.editingTarget, isCompact: true,
                        titleOverride: .mediaAccessibilityPartDescription(
                            String(localized: partLabel(part.kind)).localizedLowercase
                        ))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var creditLayout: some View {
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
                    .accessibilityHidden(true)
                Text(credit.label)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(credit.label))
            .accessibilityValue(Text(verbatim: credit.first.drawerName))
        }
    }

    private struct Credit {
        let first: ExquisiteCorpseRevealContent.Part
        let label: LocalizedStringResource
    }

    private var credits: [Credit] {
        var byDrawer: [[ExquisiteCorpseRevealContent.Part]] = []
        for part in parts {
            if let index = byDrawer.firstIndex(where: { $0[0].drawerIsMe == part.drawerIsMe }) {
                byDrawer[index].append(part)
            } else {
                byDrawer.append([part])
            }
        }
        return byDrawer.flatMap { drawn -> [Credit] in
            if let label = Self.combinedLabel(drawn.map(\.kind)) {
                return [Credit(first: drawn[0], label: label)]
            }
            return drawn.map { Credit(first: $0, label: partLabel($0.kind)) }
        }
    }

    private static func combinedLabel(_ kinds: [ExquisiteCorpsePartKind]) -> LocalizedStringResource? {
        if kinds == [.head, .legs] { return .exquisiteCorpseRevealPartsHeadAndLegs }
        if kinds == [.body, .feet] { return .exquisiteCorpseRevealPartsBodyAndFeet }
        return nil
    }

    private func partLabel(_ kind: ExquisiteCorpsePartKind) -> LocalizedStringResource {
        switch kind {
        case .head: .exquisiteCorpseRevealPartsHead
        case .body: .exquisiteCorpseRevealPartsBody
        case .legs: .exquisiteCorpseRevealPartsLegs
        case .feet: .exquisiteCorpseRevealPartsFeet
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

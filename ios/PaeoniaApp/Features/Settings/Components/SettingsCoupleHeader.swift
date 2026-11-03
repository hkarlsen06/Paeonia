import SwiftUI

/// The couple at the top of the More tab: both photos joined by a heart, both names,
/// and how long they have been together.
///
/// Tapping your own photo opens your profile. Tapping
/// your partner's photo opens what you call them. The rows below open the same
/// screens, for anyone who doesn't think to tap a photo.
struct SettingsCoupleHeader: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    /// The day the relationship started (`yyyy-MM-dd`). The count line hides until
    /// the couple sets it.
    let relationshipStartedOn: String?
    var onOpenProfile: (() -> Void)?
    /// Nil while there is no partner, so the photo is not a button.
    var onOpenPartner: (() -> Void)?

    @Environment(\.avatarStyling) private var avatarStyling
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .title) private var scaledAvatarSize: CGFloat = 76
    /// Nothing else re-renders the header overnight, so the day count refreshes this.
    @State private var now = Date()

    private static let connectorWidth: CGFloat = 44
    private static let heartCircleDiameter: CGFloat = 30

    private var avatarSize: CGFloat { min(scaledAvatarSize, 104) }
    /// Room for a name a little wider than the photo above it.
    private var columnWidth: CGFloat { avatarSize + PaeoniaSpacing.space32 }

    private var decorations: CoupleAvatarDecorations {
        avatarStyling?.decorations ?? CoupleAvatarDecorations()
    }

    private var decorationClearance: CGFloat {
        avatarSize * max(decorations.own.outset, decorations.partner.outset)
    }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            peopleLayout {
                tappable(
                    person(
                        name: currentName, photo: currentProfilePhotoAssetID,
                        tint: .paeoniaPartnerOne, decoration: decorations.own
                    ),
                    action: onOpenProfile,
                    label: Text(.settingsProfileSectionTitle),
                    identifier: "settings.coupleHeader.profile"
                )
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.paeoniaAccentPrimary)
                        .accessibilityHidden(true)
                } else {
                    connector
                }
                tappable(
                    person(
                        name: partnerName, photo: partnerProfilePhotoAssetID,
                        tint: .paeoniaPartnerTwo, decoration: decorations.partner
                    ),
                    action: onOpenPartner,
                    label: Text(.settingsPartnerNicknameRowTitle(partnerName)),
                    identifier: "settings.coupleHeader.partner"
                )
            }

            if let relationshipStartedOn, let daysTogether {
                togetherLine(startedOn: relationshipStartedOn, days: daysTogether)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PaeoniaSpacing.space8)
        .onCalendarDayChange { now = Date() }
    }

    private var peopleLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
    }

    @ViewBuilder
    private func tappable(
        _ content: some View, action: (() -> Void)?, label: Text, identifier: String
    ) -> some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(label)
                .accessibilityIdentifier(identifier)
        } else {
            content.accessibilityElement(children: .combine)
        }
    }

    private func person(
        name: String, photo: UUID?, tint: Color, decoration: AvatarDecoration
    ) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            PaeoniaDecoratedAvatar(
                mediaAssetID: photo, name: name, tint: tint, size: avatarSize, decoration: decoration
            )
            .padding(.vertical, decorationClearance)
            .accessibilityHidden(true)

            Text(name)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : columnWidth)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
    }

    /// A line from photo to photo with the heart on it. The line overflows the
    /// connector into both columns so it touches each photo's edge.
    private var connector: some View {
        ZStack {
            Rectangle()
                .fill(.paeoniaAccentPrimary.opacity(0.6))
                .frame(width: columnWidth + Self.connectorWidth - avatarSize, height: 1.5)

            Circle()
                .fill(.paeoniaBackgroundPrimary)
                .frame(width: Self.heartCircleDiameter, height: Self.heartCircleDiameter)

            Circle()
                .stroke(.paeoniaAccentPrimary.opacity(0.72), lineWidth: 1.2)
                .frame(width: Self.heartCircleDiameter, height: Self.heartCircleDiameter)

            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
        }
        .frame(width: Self.connectorWidth, height: avatarSize + 2 * decorationClearance)
        .accessibilityHidden(true)
    }

    /// "Together for 6 months and 3 days", or the first-day line while the count is
    /// still 0. Same wording as the milestone timeline.
    private func togetherLine(startedOn: String, days: Int) -> some View {
        Group {
            if days == 0 {
                Text(.homeMilestoneTimelineFirstDay)
            } else {
                Text(.homeMilestoneTimelineTogetherFor(
                    RelationshipTimelineView.togetherText(startedOn: startedOn, now: now)
                ))
            }
        }
        .font(PaeoniaTypography.body)
        .foregroundStyle(.paeoniaTextSecondary)
        .multilineTextAlignment(.center)
    }

    private var daysTogether: Int? {
        guard let relationshipStartedOn else { return nil }
        return RelationshipMilestoneCalculator()
            .daysTogether(startedOn: relationshipStartedOn, now: now)
            .map { max(0, $0) }
    }
}

#Preview {
    List {
        SettingsCoupleHeader(
            currentName: "Hjalmar",
            currentProfilePhotoAssetID: nil,
            partnerName: "Oda",
            partnerProfilePhotoAssetID: nil,
            relationshipStartedOn: "2025-03-12"
        )
        .listRowBackground(Color.clear)
    }
    .paeoniaGroupedList()
    .preferredColorScheme(.dark)
}

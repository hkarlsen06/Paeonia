import SwiftUI

/// The couple at the top of the Us tab: both photos joined by a heart, both names,
/// and how long they have been together.
///
/// It only shows who the couple is. The rows below it edit things: the profile row
/// for the user's own name and photo, and the relationship date row for the count.
struct SettingsCoupleHeader: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    /// The day the relationship started (`yyyy-MM-dd`). The count line hides until
    /// the couple sets it.
    let relationshipStartedOn: String?

    @ScaledMetric(relativeTo: .title) private var scaledAvatarSize: CGFloat = 76
    /// Nothing else re-renders the header overnight, so the day count refreshes this.
    @State private var now = Date()

    private static let connectorWidth: CGFloat = 44
    private static let heartCircleDiameter: CGFloat = 30

    private var avatarSize: CGFloat { min(scaledAvatarSize, 104) }
    /// Room for a name a little wider than the photo above it.
    private var columnWidth: CGFloat { avatarSize + PaeoniaSpacing.space32 }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            HStack(alignment: .top, spacing: 0) {
                person(name: currentName, photo: currentProfilePhotoAssetID, tint: .paeoniaPartnerOne)
                connector
                person(name: partnerName, photo: partnerProfilePhotoAssetID, tint: .paeoniaPartnerTwo)
            }

            if let daysTogether {
                togetherLine(days: daysTogether)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PaeoniaSpacing.space8)
        // Read as one line: both names, then the count.
        .accessibilityElement(children: .combine)
        .onCalendarDayChange { now = Date() }
    }

    private func person(name: String, photo: UUID?, tint: Color) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            PaeoniaProfilePhotoAvatar(mediaAssetID: photo, name: name, tint: tint, size: avatarSize)
                .accessibilityHidden(true)

            Text(name)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: columnWidth)
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
        .frame(width: Self.connectorWidth, height: avatarSize)
        .accessibilityHidden(true)
    }

    /// "Together for 186 days", or the first-day line while the count is still 0.
    /// Same wording as the milestone timeline.
    private func togetherLine(days: Int) -> some View {
        Group {
            if days == 0 {
                Text(.homeMilestoneTimelineFirstDay)
            } else {
                Text(.homeMilestoneTimelineTogetherFor(RelationshipTimelineView.daysText(days)))
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

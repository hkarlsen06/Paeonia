import SwiftUI

/// An avatar marker on the map. A partner's marker dims once its last-known
/// location is 24 hours old; the plain-language status below the map carries the
/// same state so color/opacity is never the only signal.
struct MapAvatarPin: View {
    let name: String
    let assetID: UUID?
    let tint: Color
    let capturedAt: Date
    var wasStaleAtLastRefresh = false
    var dimsWhenStale = false

    private static let avatarDiameter: CGFloat = 36
    private static let staleMarkerOpacity = 0.5
    private static let refreshInterval: TimeInterval = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { context in
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: assetID,
                name: name,
                tint: tint,
                size: Self.avatarDiameter
            )
            .opacity(opacity(asOf: context.date))
        }
    }

    private func opacity(asOf now: Date) -> Double {
        guard dimsWhenStale,
              LocationDisplayRecency.resolve(
                  capturedAt: capturedAt,
                  now: now,
                  wasStaleAtLastRefresh: wasStaleAtLastRefresh
              ) == .stale
        else {
            return 1
        }
        return Self.staleMarkerOpacity
    }
}

/// Keeps the recorded time and stale warning available as ordinary text below
/// the map, including for VoiceOver users who cannot inspect marker opacity.
struct PartnerLocationRecordedStatus: View {
    let partnerName: String
    let capturedAt: Date
    let wasStaleAtLastRefresh: Bool

    private static let refreshInterval: TimeInterval = 30
    /// Captures younger than this read "just now" instead of "in 12 seconds".
    private static let justNowThreshold: TimeInterval = 60
    /// Wide units ("2 hours ago") read better aloud than abbreviated ones ("2 hr. ago").
    private static let relativeStyle = Date.RelativeFormatStyle(
        presentation: .named,
        unitsStyle: .wide
    )

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.refreshInterval)) { context in
            HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8) {
                Image(systemName: "clock.fill")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)

                Text(status(asOf: context.date))
                    .font(PaeoniaTypography.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.paeoniaTextSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func status(asOf now: Date) -> LocalizedStringResource {
        let displayedDate = min(capturedAt, now)
        let relativeTime = displayedDate.formatted(Self.relativeStyle)
        switch LocationDisplayRecency.resolve(
            capturedAt: capturedAt,
            now: now,
            wasStaleAtLastRefresh: wasStaleAtLastRefresh
        ) {
        case .recent:
            if now.timeIntervalSince(capturedAt) < Self.justNowThreshold {
                return .homeMapRecordedJustNow(partnerName)
            }
            return .homeMapRecordedRecent(partnerName, relativeTime)
        case .stale:
            return .homeMapRecordedStale(partnerName, relativeTime)
        }
    }
}

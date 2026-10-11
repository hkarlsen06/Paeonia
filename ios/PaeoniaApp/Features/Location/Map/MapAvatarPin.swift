import SwiftUI

/// An avatar marker on the map. A partner's marker dims once its last-known
/// location is 24 hours old. VoiceOver reads the stale state from the map's
/// accessibility value, so opacity is never the only signal.
struct MapAvatarPin: View {
    let name: String
    let assetID: UUID?
    let tint: Color
    let capturedAt: Date
    var wasStaleAtLastRefresh = false
    var dimsWhenStale = false

    static let avatarDiameter: CGFloat = 36
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

/// How old the partner's location is. The map shows the short form ("3 min").
/// VoiceOver reads the full sentence, since it can't see the dimmed marker.
enum PartnerLocationRecordedStatus {
    /// Captures younger than this read "just now" instead of "in 12 seconds".
    private static let justNowThreshold: TimeInterval = 60
    /// Wide units ("2 hours ago") read better aloud than abbreviated ones ("2 hr. ago").
    private static let relativeStyle = Date.RelativeFormatStyle(
        presentation: .named,
        unitsStyle: .wide
    )

    /// "Just now", "3 min", "2 hr", "4 days".
    static func shortAge(capturedAt: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(capturedAt)
        guard seconds >= justNowThreshold else {
            return String(localized: .homeMapAgeJustNow)
        }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 1)
        )
    }

    static func accessibilityText(
        partnerName: String,
        capturedAt: Date,
        wasStaleAtLastRefresh: Bool,
        now: Date = .now
    ) -> LocalizedStringResource {
        let displayedDate = min(capturedAt, now)
        let relativeTime = displayedDate.formatted(relativeStyle)
        switch LocationDisplayRecency.resolve(
            capturedAt: capturedAt,
            now: now,
            wasStaleAtLastRefresh: wasStaleAtLastRefresh
        ) {
        case .recent:
            if now.timeIntervalSince(capturedAt) < justNowThreshold {
                return .homeMapRecordedJustNow(partnerName)
            }
            return .homeMapRecordedRecent(partnerName, relativeTime)
        case .stale:
            return .homeMapRecordedStale(partnerName, relativeTime)
        }
    }
}

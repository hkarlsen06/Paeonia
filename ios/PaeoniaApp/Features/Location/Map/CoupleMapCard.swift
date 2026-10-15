import MapKit
import SwiftUI
import UIKit

/// The top card on the Home tab. With a map to show it is a 2:1 tile: a dark-mode map
/// that fills the whole card, framed to show both partners with their avatars, and
/// the live distance overlaid at the bottom. The map is rendered with
/// `MKMapSnapshotter` so it has no Apple Maps attribution overlay and so the camera
/// framing and pin placement are fully under our control.
///
/// When there is no map, the card shrinks to a compact row (`MapEmptyState`) that
/// explains why and, where it helps, offers one action. That keeps the rest of the
/// Home tab on screen for couples who do not share location. `.loading` keeps the 2:1
/// shape because it usually resolves to a map, so the card does not shrink and
/// then grow back. Both shapes share the same corner radius, stroke, and shadow.
struct CoupleMapCard: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    let state: CoupleMapState
    var onPromptCurrentLocation: () -> Void = {}
    /// Sends and receives hearts. Nil leaves the card without them (previews).
    var hearts: HeartsViewModel?

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        switch state {
        case let .ready(current, partner, partnerWasStaleAtLastRefresh):
            readyContent(
                current: current,
                partner: partner,
                partnerWasStaleAtLastRefresh: partnerWasStaleAtLastRefresh
            )
        case .loading:
            mapTile {
                Color.paeoniaBackgroundSecondary
            }
            .accessibilityHidden(true)
        case .currentUnknown:
            emptyCard(
                MapEmptyState(
                    title: .homeMapCurrentUnknownTitle,
                    message: .homeMapCurrentUnknownMessage,
                    systemImage: "location.slash.fill",
                    actionTitle: .homeMapCurrentUnknownButton,
                    actionSystemImage: "location.fill",
                    action: onPromptCurrentLocation
                )
            )
        case .locatingCurrent:
            emptyCard(
                MapEmptyState(
                    title: .homeMapLocatingTitle,
                    message: .homeMapLocatingMessage,
                    systemImage: "location.fill",
                    showsProgress: true
                )
            )
        case .currentLocationMissing:
            emptyCard(
                MapEmptyState(
                    title: .homeMapCurrentMissingTitle,
                    message: .homeMapCurrentMissingMessage,
                    systemImage: "location.slash.fill",
                    actionTitle: .homeMapCurrentMissingButton,
                    actionSystemImage: "arrow.clockwise",
                    action: onPromptCurrentLocation
                )
            )
        case .locationAccessOff:
            emptyCard(
                MapEmptyState(
                    title: .homeMapAccessOffTitle,
                    message: .homeMapAccessOffMessage(partnerName),
                    systemImage: "location.slash.fill",
                    actionTitle: .commonOpenSettings,
                    actionSystemImage: "gear",
                    action: openAppSettings
                )
            )
        case .waitingForPartnerLocation:
            emptyCard(
                MapEmptyState(
                    title: .homeMapPartnerWaitingTitle(partnerName),
                    message: .homeMapPartnerWaitingMessage(partnerName),
                    systemImage: "location.fill"
                )
            )
        case let .partnerUnknown(reason):
            partnerUnknownCard(reason)
        }
    }

    private static func areTogether(
        current: LocationPoint,
        partner: LocationPoint,
        partnerWasStaleAtLastRefresh: Bool
    ) -> Bool {
        CoupleMapFraming.areTogether(
            current: current.coordinate,
            partner: partner.coordinate,
            partnerIsStale: LocationDisplayRecency.resolve(
                capturedAt: partner.capturedAt,
                now: .now,
                wasStaleAtLastRefresh: partnerWasStaleAtLastRefresh
            ) == .stale
        )
    }

    private static func distanceAccessibilityText(
        current: LocationPoint,
        partner: LocationPoint,
        isTogether: Bool
    ) -> String {
        guard !isTogether else {
            return String(localized: .homeMapTogetherAccessibility)
        }
        let distanceText = CoupleMapSnapshot.formattedDistance(from: current.coordinate, to: partner.coordinate)
        return String(localized: .homeMapDistanceAccessibility(distanceText))
    }

    private func readyContent(
        current: LocationPoint,
        partner: LocationPoint,
        partnerWasStaleAtLastRefresh: Bool
    ) -> some View {
        let isTogether = Self.areTogether(
            current: current,
            partner: partner,
            partnerWasStaleAtLastRefresh: partnerWasStaleAtLastRefresh
        )

        let recordedText = PartnerLocationRecordedStatus.accessibilityText(
            partnerName: partnerName,
            capturedAt: partner.capturedAt,
            wasStaleAtLastRefresh: partnerWasStaleAtLastRefresh
        )

        // Tap blows heart between avatars; long press opens Maps.
        return mapTile {
            CoupleMapSnapshot(
                currentName: currentName,
                currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                currentCoordinate: current.coordinate,
                currentCapturedAt: current.capturedAt,
                partnerName: partnerName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                partnerCoordinate: partner.coordinate,
                partnerCapturedAt: partner.capturedAt,
                partnerWasStaleAtLastRefresh: partnerWasStaleAtLastRefresh,
                isTogether: isTogether,
                onLongPress: {
                    openInAppleMaps(current: current, partner: partner)
                },
                onSendHeart: { hearts?.tap() },
                incomingBurst: hearts?.incomingBurst
            )
        }
        .overlay(alignment: .topLeading) { incomingLinePill }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: hearts?.incomingLine)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.homeMapAccessibilityLabel(partnerName)))
        .accessibilityValue(Text(verbatim: [
            Self.distanceAccessibilityText(current: current, partner: partner, isTogether: isTogether),
            String(localized: recordedText),
        ].joined(separator: ", ")))
        .accessibilityHint(Text(.homeMapOpenHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            openInAppleMaps(current: current, partner: partner)
        }
        .accessibilityAction(named: Text(.heartsSendAction)) {
            hearts?.tap()
        }
    }

    /// "Robin sent you 14 hearts" over the map's top corner. The map's own text sits
    /// on the right, and the Apple Maps mark on the bottom left.
    @ViewBuilder
    private var incomingLinePill: some View {
        if let line = hearts?.incomingLine {
            HeartsIncomingLine(text: line)
                .padding(.horizontal, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space8)
                .background(Color.paeoniaBackgroundSecondary.opacity(0.9), in: Capsule())
                .padding(PaeoniaSpacing.space12)
                .transition(.opacity)
        }
    }

    private func partnerUnknownCard(_ reason: PartnerLocationVisibilityState) -> some View {
        emptyCard(partnerUnknownState(for: reason), allowsHearts: Self.canSendHearts(whenPartnerUnknown: reason))
    }

    private func partnerUnknownState(for reason: PartnerLocationVisibilityState) -> MapEmptyState {
        switch reason {
        case .relationshipEnded:
            MapEmptyState(
                title: .homeMapRelationshipEndedTitle,
                message: .homeMapRelationshipEndedMessage,
                systemImage: "location.slash.fill"
            )
        case .unknown:
            MapEmptyState(
                title: .homeMapUnavailableTitle,
                message: .homeMapUnavailableMessage,
                systemImage: "map"
            )
        case .disabled, .notSharing, .visible:
            MapEmptyState(
                title: .homeMapPartnerUnknownTitle(partnerName),
                message: .homeMapPartnerUnknownMessage(partnerName),
                systemImage: "location.slash.fill"
            )
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(url)
    }

    private func openInAppleMaps(current: LocationPoint, partner: LocationPoint) {
        let you = MKMapItem(
            location: CLLocation(latitude: current.latitude, longitude: current.longitude),
            address: nil
        )
        you.name = currentName
        let partner = MKMapItem(
            location: CLLocation(latitude: partner.latitude, longitude: partner.longitude),
            address: nil
        )
        partner.name = partnerName
        MKMapItem.openMaps(
            with: [you, partner],
            launchOptions: [MKLaunchOptionsMapTypeKey: NSNumber(value: MKMapType.standard.rawValue)]
        )
    }

    /// The compact card for one of the "no map yet" messages. It has no fixed shape,
    /// so it is as tall as its text needs. Paired couples get the heart row too.
    private func emptyCard(_ content: MapEmptyState, allowsHearts: Bool = true) -> some View {
        var content = content
        if allowsHearts, let hearts {
            content.hearts = MapHeartsButton(
                currentName: currentName,
                currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                partnerName: partnerName,
                partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                incomingBurst: hearts.incomingBurst,
                onSend: { hearts.tap() }
            )
            content.incomingLine = hearts.incomingLine
        }
        return mapTileSurface(content)
    }

    /// Nobody receives hearts once the relationship has ended.
    private static func canSendHearts(whenPartnerUnknown reason: PartnerLocationVisibilityState) -> Bool {
        if case .relationshipEnded = reason {
            return false
        }
        return true
    }

    private func mapTile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        mapTileSurface(content().aspectRatio(2, contentMode: .fit))
    }

    private func mapTileSurface<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }
}

extension LocationPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

#if DEBUG
private func previewCard(_ state: CoupleMapState, hearts: HeartsViewModel? = nil) -> some View {
    CoupleMapCard(
        currentName: "Hjalmar",
        currentProfilePhotoAssetID: nil,
        partnerName: "Oda",
        partnerProfilePhotoAssetID: nil,
        state: state,
        hearts: hearts
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Partner not sharing") {
    previewCard(.partnerUnknown(.notSharing))
}

#Preview("Partner not sharing, with hearts") {
    previewCard(.partnerUnknown(.notSharing), hearts: HeartsViewModel())
}

#Preview("Locating") {
    previewCard(.locatingCurrent)
}

#Preview("Share location") {
    previewCard(.currentUnknown)
}

#Preview("Share location, accessibility size") {
    previewCard(.currentUnknown)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Loading") {
    previewCard(.loading)
}

#Preview("Location access off") {
    previewCard(.locationAccessOff)
}

#Preview("Waiting for partner") {
    previewCard(.waitingForPartnerLocation)
}

#Preview("Ready") {
    previewCard(
        .ready(
            current: LocationPoint(latitude: 59.9139, longitude: 10.7522, capturedAt: .now),
            partner: LocationPoint(
                latitude: 60.3913,
                longitude: 5.3221,
                capturedAt: .now.addingTimeInterval(-300)
            ),
            partnerWasStaleAtLastRefresh: false
        )
    )
}
#endif

import MapKit
import SwiftUI
import UIKit

/// The map tile on the Us tab: a dark-mode map that fills the whole card, framed
/// to show both partners with their avatars, and the live distance overlaid at the
/// bottom. The map is rendered with `MKMapSnapshotter` so it has no Apple Maps
/// attribution overlay and so the camera framing and pin placement are fully under
/// our control. When there is no map to show, the tile explains why and, where it
/// helps, offers one action.
struct CoupleMapCard: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    let state: CoupleMapState
    var onPromptCurrentLocation: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

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
            emptyTile(
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
            emptyTile(
                MapEmptyState(
                    title: .homeMapLocatingTitle,
                    message: .homeMapLocatingMessage,
                    systemImage: "location.fill",
                    showsProgress: true
                )
            )
        case .currentLocationMissing:
            emptyTile(
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
            emptyTile(
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
            emptyTile(
                MapEmptyState(
                    title: .homeMapPartnerWaitingTitle(partnerName),
                    message: .homeMapPartnerWaitingMessage(partnerName),
                    systemImage: "location.fill"
                )
            )
        case let .partnerUnknown(reason):
            emptyTile(partnerUnknownState(for: reason))
        }
    }

    private static func areTogether(
        current: LocationPoint,
        partner: LocationPoint,
        partnerWasStaleAtLastRefresh: Bool
    ) -> Bool {
        CoupleMapFraming.areTogether(
            current: current.coordinate,
            currentCapturedAt: current.capturedAt,
            partner: partner.coordinate,
            partnerCapturedAt: partner.capturedAt,
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
                }
            )
        }
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
                systemImage: "wifi.slash"
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

    /// A tile holding one of the "no map yet" messages. At accessibility text sizes the
    /// fixed 2:1 shape is dropped so the text has room to grow.
    private func emptyTile(_ content: MapEmptyState) -> some View {
        mapTile(preservesAspectRatio: !dynamicTypeSize.isAccessibilitySize) {
            content
        }
    }

    @ViewBuilder
    private func mapTile<Content: View>(
        preservesAspectRatio: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if preservesAspectRatio {
            mapTileSurface(content().aspectRatio(2, contentMode: .fit))
        } else {
            mapTileSurface(content())
        }
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
private func previewCard(_ state: CoupleMapState) -> some View {
    CoupleMapCard(
        currentName: "Hjalmar",
        currentProfilePhotoAssetID: nil,
        partnerName: "Oda",
        partnerProfilePhotoAssetID: nil,
        state: state
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Partner not sharing") {
    previewCard(.partnerUnknown(.notSharing))
}

#Preview("Locating") {
    previewCard(.locatingCurrent)
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

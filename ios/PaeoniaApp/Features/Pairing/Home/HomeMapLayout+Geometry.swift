import CoreLocation
import SwiftUI

struct HomeMapAvatarPoints: Equatable {
    let own: CGPoint
    let partner: CGPoint
}

struct HomeMapCouple {
    let current: LocationPoint
    let partner: LocationPoint
    let currentCoordinate: CLLocationCoordinate2D
    let partnerCoordinate: CLLocationCoordinate2D
    let partnerWasStaleAtLastRefresh: Bool

    /// Close enough that the map shows one city, so both avatars sit side by side in the middle.
    var isNear: Bool {
        CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
            .distance(from: CLLocation(latitude: partnerCoordinate.latitude, longitude: partnerCoordinate.longitude))
            < CoupleMapFraming.minimumSpanMeters / CoupleMapFraming.paddingFactor
    }
}

/// The screen the page sits in, in the scroll content's coordinates, which start at the top
/// of the screen.
struct HomeMapScreen {
    let width: CGFloat
    let topInset: CGFloat
    /// Where the safe area ends, at the top of the tab bar.
    let visibleBottom: CGFloat

    init(geo: GeometryProxy) {
        width = geo.size.width
        topInset = geo.safeAreaInsets.top
        visibleBottom = topInset + geo.size.height
    }

    /// The page's height when the cards fit: the last card ends just above the tab bar.
    var fillHeight: CGFloat { visibleBottom - PaeoniaSpacing.space8 }
    /// At least room for the avatars, plus the fade.
    var shortestBand: CGFloat { topInset + 212 + HomeMapMetrics.fadeHeight }
    /// The map view's own height: the tallest the band can be.
    var mapHeight: CGFloat { visibleBottom + HomeMapMetrics.fadeHeight }
}

struct HomeMapMetrics {
    static let fadeHeight: CGFloat = 260
    static var cardsOverlap: CGFloat { fadeHeight - PaeoniaSpacing.space16 }

    let screen: HomeMapScreen
    let bandHeight: CGFloat
    /// The bottom of the last row where the map is fully shown.
    let framedBottom: CGFloat
    /// Where the avatars' centers may go, in the map's coordinates.
    let framedBox: CGRect
    /// The open map, less half an avatar, so a held avatar stays whole and clear of the
    /// bar and the first card.
    let avatarBounds: CGRect

    var width: CGFloat { screen.width }
    /// The fade starts a little above the cards and runs to the bottom of the band.
    var fadeLength: CGFloat { Self.fadeHeight + 20 }

    init(screen: HomeMapScreen, bandHeight: CGFloat, avatarSize: CGFloat, isNear: Bool) {
        self.screen = screen
        self.bandHeight = bandHeight
        framedBottom = bandHeight - Self.fadeHeight
        let cardsTop = framedBottom + PaeoniaSpacing.space16
        // The avatars are centered in the open map between the streak pill and the first
        // card. The bar's glass is off at rest, so the pill is where the space starts.
        // Together they sit side by side in the middle. Apart, they may go anywhere in that
        // space with the same margin above and below, room for a note bubble each way, so
        // the pair always stays centered.
        let pillBottom = screen.topInset + PaeoniaSpacing.compactButtonHeight
        let half = avatarSize / 2
        let width = screen.width
        // An avatar's edge never comes closer to the screen's sides than the cards do.
        let sideMargin = PaeoniaSpacing.screenHorizontalPadding
        avatarBounds = CGRect(
            x: half + sideMargin,
            y: pillBottom + PaeoniaSpacing.space8 + half,
            width: max(width - avatarSize - 2 * sideMargin, 1),
            height: max(cardsTop - pillBottom - avatarSize - 2 * PaeoniaSpacing.space8, 1)
        )
        if isNear {
            framedBox = CGRect(x: 0, y: (pillBottom + cardsTop) / 2 - 1, width: width, height: 2)
        } else {
            let margin = PaeoniaSpacing.space8 + 44 + half
            let top = pillBottom + margin
            let bottom = cardsTop - margin
            let side = half + sideMargin
            framedBox = CGRect(x: side, y: top, width: width - 2 * side, height: max(bottom - top, 1))
        }
    }
}

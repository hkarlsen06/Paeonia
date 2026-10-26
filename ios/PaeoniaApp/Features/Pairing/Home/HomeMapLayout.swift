import CoreLocation
import SwiftUI

/// PROTOTYPE. Home with the couple's map as its header. The map fades on behind the cards,
/// both avatars sit on it with their stories and notes, and the cards follow in one plain
/// scroll view. The mark and the streak stay at the top in a bar that turns to glass once
/// the cards scroll under it, like a navigation bar.
struct HomeMapReadyLayout<Header: View, Sheet: View>: View {
    let current: LocationPoint
    let partner: LocationPoint
    let stories: StoriesViewModel?
    let storyPeople: StoryPeople?
    @ViewBuilder let header: Header
    @ViewBuilder let sheet: Sheet

    @AppStorage("proto.home.avatarSize") private var avatarSize: Double = 72
    @AppStorage("proto.home.fakePartner") private var fakePartner: FakePartnerPlace = .real
    @State private var avatarPoints: AvatarPoints?
    @State private var scrollOffset: CGFloat = 0
    /// How tall the cards are, and where the screen ends above the tab bar. When the cards
    /// fit, the map takes the rest of the screen and the page doesn't scroll.
    @State private var sheetHeight: CGFloat = 0

    private var partnerCoordinate: CLLocationCoordinate2D {
        fakePartner.coordinate ?? partner.coordinate
    }

    /// Close enough that the map shows one city, so both avatars sit side by side in the middle.
    private var isNear: Bool {
        CLLocation(latitude: current.latitude, longitude: current.longitude)
            .distance(from: CLLocation(latitude: partnerCoordinate.latitude, longitude: partnerCoordinate.longitude))
            < CoupleMapFraming.minimumSpanMeters / CoupleMapFraming.paddingFactor
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = Metrics(geo: geo, sheetHeight: sheetHeight, avatarSize: avatarSize, isNear: isNear)
            ScrollView {
                VStack(spacing: 0) {
                    mapHeader(metrics)
                    sheet
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
                        // The cards start just under the map's last full row, and the map fades on behind them.
                        .padding(.top, -metrics.cardsOverlap)
                }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            // When everything fits, there is nothing to scroll to, so the page stays still.
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)
            // Like a navigation bar: no glass at rest over the map, glass as soon as Home scrolls.
            .scrollEdgeEffectHidden(scrollOffset <= 1, for: .top)
            .safeAreaBar(edge: .top) {
                header
                    // Sits where a navigation bar puts its title, under the Dynamic Island.
                    .overlay {
                        HomeMapDistanceLine(
                            current: current,
                            partner: partner,
                            partnerCoordinate: partnerCoordinate,
                            mapDirection: HomeMapLibreView.camera(
                                current: current.coordinate,
                                partner: partnerCoordinate,
                                isNear: isNear,
                                area: metrics.framedBox,
                                viewSize: CGSize(width: metrics.width, height: metrics.bandHeight)
                            ).direction
                        )
                        .contextMenu { prototypeMenu }
                    }
                    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                    // A navigation bar is 54 points tall, so its glass reaches past the 44 point pill.
                    .padding(.bottom, PaeoniaSpacing.space12)
            }
        }
    }

    // MARK: Map

    private func mapHeader(_ metrics: Metrics) -> some View {
        ZStack(alignment: .top) {
            HomeMapLibreView(
                current: current.coordinate,
                partner: partnerCoordinate,
                isNear: isNear,
                framedBox: metrics.framedBox,
                avatarSize: avatarSize
            ) { own, partner in
                avatarPoints = AvatarPoints(own: own, partner: partner)
            }
            .mask { fadeMask(metrics) }

            avatars(metrics)
        }
        .frame(height: metrics.bandHeight)
        // A pull down keeps the map against the top of the screen.
        .visualEffect { content, proxy in
            content.offset(y: min(0, -proxy.frame(in: .scrollView(axis: .vertical)).minY))
        }
    }

    /// Eases out over a long stretch, so the map runs into the cards instead of ending.
    private func fadeMask(_ metrics: Metrics) -> some View {
        let start = metrics.fadeStart
        let length = 1 - start
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: start),
                .init(color: .black.opacity(0.75), location: start + length * 0.15),
                .init(color: .black.opacity(0.45), location: start + length * 0.35),
                .init(color: .black.opacity(0.2), location: start + length * 0.6),
                .init(color: .black.opacity(0.06), location: start + length * 0.82),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func avatars(_ metrics: Metrics) -> some View {
        if let stories, let storyPeople, let raw = avatarPoints {
            let points = kept(separated(raw), inside: metrics.avatarBounds)
            HomeStoriesStrip(
                viewModel: stories,
                people: storyPeople,
                avatarSize: avatarSize,
                arrange: { own, partner in
                    AnyView(
                        ZStack {
                            own.position(points.own)
                            partner.position(points.partner)
                        }
                    )
                }
            )
        }
    }

    /// Holds each avatar inside the open map. Only a couple on opposite sides of the world
    /// can be too far apart for the widest zoom, and then an avatar waits at the edge, on
    /// the side its partner is.
    private func kept(_ points: AvatarPoints, inside bounds: CGRect) -> AvatarPoints {
        func keep(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
        }
        return AvatarPoints(own: keep(points.own), partner: keep(points.partner))
    }

    private func separated(_ points: AvatarPoints) -> AvatarPoints {
        // Wide enough that the two note bubbles never touch.
        let minimum = max(StoryNoteBubble.maxWidth + PaeoniaSpacing.space8, avatarSize + PaeoniaSpacing.space16)
        guard isNear else {
            // Apart: pushed away from each other along the line between the two places,
            // so north stays north, with room for a note bubble when one sits above the other.
            let apart = max(minimum, avatarSize + 56)
            let (own, partner) = CoupleMapFraming.separated(points.own, points.partner, minimumDistance: apart)
            return AvatarPoints(own: own, partner: partner)
        }
        // Together: side by side around the midpoint, you on the left.
        let mid = CGPoint(x: (points.own.x + points.partner.x) / 2, y: (points.own.y + points.partner.y) / 2)
        return AvatarPoints(
            own: CGPoint(x: mid.x - minimum / 2, y: mid.y),
            partner: CGPoint(x: mid.x + minimum / 2, y: mid.y)
        )
    }

    @ViewBuilder
    private var prototypeMenu: some View {
        Picker(selection: $avatarSize) {
            Text(verbatim: "64").tag(64.0)
            Text(verbatim: "72 (today's size)").tag(72.0)
            Text(verbatim: "84").tag(84.0)
        } label: {
            Text(verbatim: "Avatar size")
        }
        Picker(selection: $fakePartner) {
            ForEach(FakePartnerPlace.allCases, id: \.self) { place in
                Text(verbatim: place.label).tag(place)
            }
        } label: {
            Text(verbatim: "Partner location")
        }
        Section(HomeMapLibreView.credit) {}
    }
}

private struct AvatarPoints: Equatable {
    let own: CGPoint
    let partner: CGPoint
}

private struct Metrics {
    let width: CGFloat
    let topInset: CGFloat
    let bandHeight: CGFloat
    let fadeHeight: CGFloat = 260
    /// The bottom of the last row where the map is fully shown.
    let framedBottom: CGFloat
    /// Where the avatars' centers may go, in the map's coordinates.
    let framedBox: CGRect
    /// The open map, less half an avatar, so a held avatar stays whole and clear of the
    /// bar and the first card.
    let avatarBounds: CGRect

    init(geo: GeometryProxy, sheetHeight: CGFloat, avatarSize: CGFloat, isNear: Bool) {
        width = geo.size.width
        topInset = geo.safeAreaInsets.top
        // The safe area ends at the top of the tab bar, in the scroll content's coordinates,
        // which start at the top of the screen.
        let visibleBottom = topInset + geo.size.height
        // At least room for the avatars. When the cards are short, the map grows until the
        // last card sits just above the tab bar.
        let shortest = topInset + 212
        let fitting = visibleBottom - PaeoniaSpacing.space8 - sheetHeight - PaeoniaSpacing.space16
        framedBottom = sheetHeight > 0 ? max(shortest, fitting) : shortest
        bandHeight = framedBottom + fadeHeight
        let cardsTop = framedBottom + PaeoniaSpacing.space16
        // The avatars are centered in the open map between the streak pill and the first
        // card. The bar's glass is off at rest, so the pill is where the space starts.
        // Together they sit side by side in the middle. Apart, they may go anywhere in that
        // space with the same margin above and below, room for a note bubble each way, so
        // the pair always stays centered.
        let pillBottom = topInset + PaeoniaSpacing.compactButtonHeight
        let half = avatarSize / 2
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

    var cardsOverlap: CGFloat { fadeHeight - PaeoniaSpacing.space16 }
    var fadeStart: CGFloat { (framedBottom - 20) / bandHeight }
}

/// "Sammen · 2 t" or "306 km · 2 t", in the bar's title position.
struct HomeMapDistanceLine: View {
    let current: LocationPoint
    let partner: LocationPoint
    let partnerCoordinate: CLLocationCoordinate2D
    /// How far the map is turned. The arrow turns back by as much, so it points north.
    var mapDirection: Double = 0

    var body: some View {
        let isTogether = CoupleMapFraming.areTogether(
            current: current.coordinate,
            partner: partnerCoordinate,
            partnerIsStale: false
        )
        TimelineView(.everyMinute) { context in
            HStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: isTogether ? "person.2.fill" : "location.north.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .rotationEffect(.degrees(isTogether ? 0 : -mapDirection))
                    .accessibilityHidden(true)
                Text(isTogether
                    ? String(localized: .homeMapTogether)
                    : CoupleMapSnapshot.formattedDistance(from: current.coordinate, to: partnerCoordinate))
                Text(verbatim: "· " + PartnerLocationRecordedStatus.shortAge(
                    capturedAt: partner.capturedAt, now: context.date
                ))
            }
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.paeoniaTextPrimary)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        }
    }
}

/// PROTOTYPE. Moves the partner's pin, to see how the map looks when the couple is apart.
enum FakePartnerPlace: String, CaseIterable {
    case real, nearby, drammen, bergen, trondheim, tromso, copenhagen, newYork, sydney

    var label: String {
        switch self {
        case .real: "Real location"
        case .nearby: "Across town (1.5 km)"
        case .drammen: "Drammen (40 km)"
        case .bergen: "Bergen"
        case .trondheim: "Trondheim"
        case .tromso: "Tromsø"
        case .copenhagen: "Copenhagen"
        case .newYork: "New York"
        case .sydney: "Sydney"
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        switch self {
        case .real: nil
        case .nearby: CLLocationCoordinate2D(latitude: 59.9270, longitude: 10.7600)
        case .drammen: CLLocationCoordinate2D(latitude: 59.7439, longitude: 10.2045)
        case .bergen: CLLocationCoordinate2D(latitude: 60.3913, longitude: 5.3221)
        case .trondheim: CLLocationCoordinate2D(latitude: 63.4305, longitude: 10.3951)
        case .tromso: CLLocationCoordinate2D(latitude: 69.6492, longitude: 18.9553)
        case .copenhagen: CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683)
        case .newYork: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        case .sydney: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093)
        }
    }
}

import MapKit
import SwiftUI

/// PROTOTYPE. Home with the couple's live map as its header. The map fades into the
/// background at the bottom, both avatars sit on it with their stories and notes, and the
/// cards follow in one plain scroll view. The map's safe area ends above the fade, which
/// keeps the Apple Maps mark on fully visible map.
struct HomeMapLayout<Header: View, Sheet: View>: View {
    let current: LocationPoint
    let partner: LocationPoint
    let stories: StoriesViewModel?
    let storyPeople: StoryPeople?
    @ViewBuilder let header: Header
    @ViewBuilder let sheet: Sheet

    @AppStorage("proto.home.avatarSize") private var avatarSize: Double = 72
    @AppStorage("proto.home.fakePartner") private var fakePartner: FakePartnerPlace = .real
    @State private var camera: MapCameraPosition = .automatic
    @State private var avatarPoints: AvatarPoints?
    @State private var scrollOffset: CGFloat = 0

    private var partnerCoordinate: CLLocationCoordinate2D {
        fakePartner.coordinate ?? partner.coordinate
    }

    /// Close enough that the map shows its smallest area, so both avatars sit in the middle.
    private var isNear: Bool {
        CLLocation(latitude: current.latitude, longitude: current.longitude)
            .distance(from: CLLocation(latitude: partnerCoordinate.latitude, longitude: partnerCoordinate.longitude))
            < CoupleMapFraming.minimumSpanMeters / CoupleMapFraming.paddingFactor
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = Metrics(geo: geo, isNear: isNear)
            ScrollView {
                VStack(spacing: 0) {
                    mapHeader(metrics)
                    sheet
                        // The cards start inside the fade, so the map runs into them.
                        .padding(.top, -metrics.cardsOverlap)
                }
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectHidden(true, for: .top)
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            // Backs the status bar once the map has scrolled away, so cards never run under the clock.
            .overlay(alignment: .top) {
                Color.paeoniaBackgroundPrimary
                    .frame(height: metrics.topInset)
                    .opacity(scrollOffset >= metrics.bandHeight - metrics.topInset ? 1 : 0)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            .onChange(of: geo.size, initial: true) { frame(metrics) }
            .onChange(of: fakePartner) { frame(metrics) }
            .onChange(of: current) { frame(metrics) }
            .onChange(of: partner) { frame(metrics) }
        }
    }

    private func frame(_ metrics: Metrics) {
        guard metrics.width > 0, metrics.framedHeight > 40 else { return }
        var region = CoupleMapFraming.region(
            current: current.coordinate,
            partner: partnerCoordinate,
            aspectRatio: metrics.width / metrics.framedHeight
        )
        if !isNear {
            // Apart, the avatars keep clear of the edges and of the distance line.
            region.span.latitudeDelta = min(region.span.latitudeDelta * 1.5, 170)
            region.span.longitudeDelta = min(region.span.longitudeDelta * 1.5, 350)
        }
        camera = .region(region)
    }

    // MARK: Map

    private func mapHeader(_ metrics: Metrics) -> some View {
        ZStack(alignment: .top) {
            Map(position: $camera, interactionModes: []) {}
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .environment(\.colorScheme, .dark)
                .grayscale(1)
                .colorMultiply(.paeoniaAccentPrimary)
                .safeAreaPadding(.top, max(metrics.framedTop, 0))
                // Ends the safe area above the fade, which is also where MapKit puts its mark.
                .safeAreaPadding(.bottom, metrics.fadeHeight)
                .onMapCameraChange(frequency: .continuous) { context in
                    guard MapScreenPoint.isUsable(context.rect) else { return }
                    avatarPoints = AvatarPoints(
                        own: MapScreenPoint.point(current.coordinate, in: context.rect, box: metrics.framedBox),
                        partner: MapScreenPoint.point(partnerCoordinate, in: context.rect, box: metrics.framedBox)
                    )
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: metrics.fadeStart),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            Color.clear
                .contentShape(Rectangle())
                .contextMenu { prototypeMenu }

            avatars

            header
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, metrics.topInset)

            HomeMapDistanceLine(current: current, partner: partner, partnerCoordinate: partnerCoordinate)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, PaeoniaSpacing.space16)
                .padding(.top, metrics.lineTop)
        }
        .frame(height: metrics.bandHeight)
        // A pull down keeps the map against the top of the screen.
        .visualEffect { content, proxy in
            content.offset(y: min(0, -proxy.frame(in: .scrollView(axis: .vertical)).minY))
        }
    }

    @ViewBuilder
    private var avatars: some View {
        if let stories, let storyPeople, let raw = avatarPoints {
            let points = separated(raw)
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

    private func separated(_ points: AvatarPoints) -> AvatarPoints {
        // Wide enough that the two note bubbles never touch.
        let minimum = max(StoryNoteBubble.maxWidth + PaeoniaSpacing.space8, avatarSize + PaeoniaSpacing.space16)
        guard isNear else {
            // Apart: pushed away from each other along the line between the two places,
            // so north stays north.
            // Room for a note bubble between them when one sits above the other.
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
    let fadeHeight: CGFloat
    /// The area the camera frames, as the map's safe area. Its bottom is the top of the
    /// fade, where the Apple Maps mark sits.
    let framedTop: CGFloat
    let framedBottom: CGFloat
    /// The top of the line with the mark and the distance.
    let lineTop: CGFloat
    let cardsOverlap: CGFloat = 40

    init(geo: GeometryProxy, isNear: Bool) {
        width = geo.size.width
        topInset = geo.safeAreaInsets.top
        fadeHeight = 96
        // Apart, the avatars sit wherever the two places are, so the map gets more height.
        bandHeight = topInset + 236 + fadeHeight - PaeoniaSpacing.space24 + (isNear ? 0 : 48)
        framedBottom = bandHeight - fadeHeight
        lineTop = framedBottom - PaeoniaSpacing.space24
        framedTop = if isNear {
            // Puts the middle of the framed area halfway between the Dynamic Island and the
            // line with the mark, where the avatars land when the couple is close.
            topInset + lineTop - framedBottom
        } else {
            // Room above the higher avatar for its note bubble.
            topInset + 56
        }
    }

    var framedHeight: CGFloat { framedBottom - framedTop }
    var framedBox: CGRect { CGRect(x: 0, y: framedTop, width: width, height: framedHeight) }
    var fadeStart: CGFloat { framedBottom / bandHeight }
}

/// Where a coordinate lands on a map view. The camera's visible rect covers the map's
/// safe area, which is `box` on screen.
enum MapScreenPoint {
    /// The first camera update can come before the map has a size.
    static func isUsable(_ rect: MKMapRect) -> Bool {
        rect.width > 0 && rect.height > 0 && rect.width.isFinite && rect.height.isFinite
    }

    static func point(_ coordinate: CLLocationCoordinate2D, in rect: MKMapRect, box: CGRect) -> CGPoint {
        let point = MKMapPoint(coordinate)
        return CGPoint(
            x: box.minX + (point.x - rect.minX) / rect.width * box.width,
            y: box.minY + (point.y - rect.minY) / rect.height * box.height
        )
    }
}

/// "Sammen · 2 t" or "306 km · 2 t", on the line with the Apple Maps mark.
struct HomeMapDistanceLine: View {
    let current: LocationPoint
    let partner: LocationPoint
    let partnerCoordinate: CLLocationCoordinate2D

    var body: some View {
        let isTogether = CoupleMapFraming.areTogether(
            current: current.coordinate,
            partner: partnerCoordinate,
            partnerIsStale: false
        )
        TimelineView(.everyMinute) { context in
            HStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: isTogether ? "person.2.fill" : "location.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(isTogether
                    ? String(localized: .homeMapTogether)
                    : CoupleMapSnapshot.formattedDistance(from: current.coordinate, to: partnerCoordinate))
                Text(verbatim: "· " + PartnerLocationRecordedStatus.shortAge(
                    capturedAt: partner.capturedAt, now: context.date
                ))
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        }
    }
}

/// PROTOTYPE. Moves the partner's pin, to see how the map looks when the couple is apart.
enum FakePartnerPlace: String, CaseIterable {
    case real, drammen, bergen, trondheim, tromso, copenhagen, newYork

    var label: String {
        switch self {
        case .real: "Real location"
        case .drammen: "Drammen (40 km)"
        case .bergen: "Bergen"
        case .trondheim: "Trondheim"
        case .tromso: "Tromsø"
        case .copenhagen: "Copenhagen"
        case .newYork: "New York"
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        switch self {
        case .real: nil
        case .drammen: CLLocationCoordinate2D(latitude: 59.7439, longitude: 10.2045)
        case .bergen: CLLocationCoordinate2D(latitude: 60.3913, longitude: 5.3221)
        case .trondheim: CLLocationCoordinate2D(latitude: 63.4305, longitude: 10.3951)
        case .tromso: CLLocationCoordinate2D(latitude: 69.6492, longitude: 18.9553)
        case .copenhagen: CLLocationCoordinate2D(latitude: 55.6761, longitude: 12.5683)
        case .newYork: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        }
    }
}

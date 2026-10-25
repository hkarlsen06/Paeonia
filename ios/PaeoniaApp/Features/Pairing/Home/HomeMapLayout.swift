import MapKit
import SwiftUI

/// PROTOTYPE. Home with the couple's live map behind everything. Both avatars sit on the
/// map with their stories and notes, and the rest of Home is one surface that scrolls up
/// over the map. Pulling down past the top opens the map full screen, and a tap on the
/// surface's edge closes it again.
struct HomeMapLayout<Header: View, Sheet: View>: View {
    let current: LocationPoint
    let partner: LocationPoint
    let partnerName: String
    let stories: StoriesViewModel?
    let storyPeople: StoryPeople?
    @ViewBuilder let header: Header
    @ViewBuilder let sheet: Sheet

    @AppStorage("proto.home.avatarSize") private var avatarSize: Double = 72
    @AppStorage("proto.home.fakePartner") private var fakePartner: FakePartnerPlace = .real
    @State private var isExpanded = UserDefaults.standard.bool(forKey: "proto.home.startExpanded")
    @State private var camera: MapCameraPosition = .automatic
    @State private var avatarPoints: AvatarPoints?
    @State private var pull: CGFloat = 0

    private static var expandPull: CGFloat { 90 }
    private static var mapSpace: String { "homeMap" }
    private static var sheetCorner: CGFloat { 32 }
    /// The mark and streak row under the status bar.
    private static var headerHeight: CGFloat { PaeoniaSpacing.compactButtonHeight }

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
            let metrics = Metrics(geo: geo, isExpanded: isExpanded, isNear: isNear)
            ScrollView {
                VStack(spacing: 0) {
                    mapLayer(metrics)
                        .frame(height: metrics.sheetTop, alignment: .top)
                        .zIndex(0)
                    sheetSurface(metrics)
                        .zIndex(1)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(isExpanded)
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: CGFloat.self) { scroll in
                -(scroll.contentOffset.y + scroll.contentInsets.top)
            } action: { _, value in
                pull = value
            }
            .onScrollPhaseChange { old, _ in
                if old == .interacting, pull > Self.expandPull {
                    setExpanded(true)
                }
            }
            .onChange(of: geo.size, initial: true) { frame(metrics) }
            .onChange(of: isExpanded) { frame(metrics) }
            .onChange(of: fakePartner) { frame(metrics) }
            .onChange(of: current) { frame(metrics) }
            .onChange(of: partner) { frame(metrics) }
        }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.snappy(duration: 0.4)) { isExpanded = expanded }
    }

    private func frame(_ metrics: Metrics) {
        guard metrics.width > 0, metrics.framedHeight > 40 else { return }
        let region = CoupleMapFraming.region(
            current: current.coordinate,
            partner: partnerCoordinate,
            aspectRatio: metrics.width / max(metrics.framedHeight, 1)
        )
        withAnimation(.snappy(duration: 0.4)) { camera = .region(region) }
    }

    // MARK: Map

    private func mapLayer(_ metrics: Metrics) -> some View {
        ZStack(alignment: .top) {
            MapReader { proxy in
                Map(position: $camera, interactionModes: isExpanded ? .all : []) {}
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .environment(\.colorScheme, .dark)
                    .grayscale(1)
                    .colorMultiply(.paeoniaAccentPrimary)
                    .safeAreaPadding(.top, metrics.framedTop)
                    // Lifts the Apple Maps mark to just above the surface's top edge.
                    .safeAreaPadding(.bottom, metrics.fullHeight - metrics.framedBottom)
                    .onMapCameraChange(frequency: .continuous) { _ in
                        updateAvatarPoints(proxy, topPadding: metrics.framedTop)
                    }
            }
            .frame(height: metrics.fullHeight)
            .overlay { avatars }
            .coordinateSpace(.named(Self.mapSpace))
            .pinnedInScroll()

            header
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, metrics.topInset)
                .pinnedInScroll()

            if isExpanded {
                prototypeMenu
                    .padding(.top, metrics.topInset + Self.headerHeight + PaeoniaSpacing.space12)
                    .padding(.trailing, PaeoniaSpacing.screenHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .pinnedInScroll()
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var avatars: some View {
        if let stories, let storyPeople, let raw = avatarPoints {
            let avatarPoints = separated(raw)
            HomeStoriesStrip(
                viewModel: stories,
                people: storyPeople,
                avatarSize: avatarSize,
                arrange: { own, partner in
                    AnyView(
                        GeometryReader { geo in
                            let origin = geo.frame(in: .named(Self.mapSpace)).origin
                            ZStack {
                                own.position(avatarPoints.own - origin)
                                partner.position(avatarPoints.partner - origin)
                            }
                        }
                    )
                }
            )
        }
    }

    /// MapProxy measures from inside the map's top safe-area padding, so the points are
    /// shifted down by it to land in the map's own space.
    private func updateAvatarPoints(_ proxy: MapProxy, topPadding: CGFloat) {
        guard let own = proxy.convert(current.coordinate, to: .named(Self.mapSpace)),
              let partner = proxy.convert(partnerCoordinate, to: .named(Self.mapSpace))
        else { return }
        avatarPoints = AvatarPoints(
            own: CGPoint(x: own.x, y: own.y + topPadding),
            partner: CGPoint(x: partner.x, y: partner.y + topPadding)
        )
    }

    private func separated(_ points: AvatarPoints) -> AvatarPoints {
        // Wide enough that the two note bubbles never touch.
        let minimum = max(StoryNoteBubble.maxWidth + PaeoniaSpacing.space8, avatarSize + PaeoniaSpacing.space16)
        let distance = hypot(points.partner.x - points.own.x, points.partner.y - points.own.y)
        guard distance < minimum else { return points }
        // Too close to show apart: side by side around the midpoint, you on the left.
        let mid = CGPoint(x: (points.own.x + points.partner.x) / 2, y: (points.own.y + points.partner.y) / 2)
        return AvatarPoints(
            own: CGPoint(x: mid.x - minimum / 2, y: mid.y),
            partner: CGPoint(x: mid.x + minimum / 2, y: mid.y)
        )
    }

    // MARK: Surface

    private func sheetSurface(_ metrics: Metrics) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.paeoniaTextTertiary)
                .frame(width: 36, height: 5)
                .padding(.top, PaeoniaSpacing.space8)
                .padding(.bottom, PaeoniaSpacing.space16)
            sheet
        }
        .frame(maxWidth: .infinity, minHeight: metrics.fullHeight, alignment: .top)
        .background(
            Color.paeoniaBackgroundPrimary,
            in: UnevenRoundedRectangle(topLeadingRadius: Self.sheetCorner, topTrailingRadius: Self.sheetCorner)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: -6)
        .overlay(alignment: .topTrailing) {
            distanceLine
                .padding(.trailing, PaeoniaSpacing.space16)
                .offset(y: -PaeoniaSpacing.space32)
        }
        .overlay {
            if isExpanded {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { setExpanded(false) }
                    .gesture(DragGesture(minimumDistance: 12).onEnded { drag in
                        if drag.translation.height < -24 { setExpanded(false) }
                    })
            }
        }
    }

    private var distanceLine: some View {
        let isTogether = CoupleMapFraming.areTogether(
            current: current.coordinate,
            partner: partnerCoordinate,
            partnerIsStale: false
        )
        return TimelineView(.everyMinute) { context in
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

    // MARK: Prototype controls

    private var prototypeMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: Circle())
        }
    }
}

private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
}

private struct AvatarPoints: Equatable {
    let own: CGPoint
    let partner: CGPoint
}

private struct Metrics {
    let width: CGFloat
    let fullHeight: CGFloat
    let topInset: CGFloat
    let sheetTop: CGFloat
    /// The area the camera frames, as the map's safe area. Its bottom also places the
    /// Apple Maps mark, on the line above the surface.
    let framedTop: CGFloat
    let framedBottom: CGFloat

    init(geo: GeometryProxy, isExpanded: Bool, isNear: Bool) {
        width = geo.size.width
        topInset = geo.safeAreaInsets.top
        fullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
        let collapsed = topInset + 236
        let expanded = fullHeight - geo.safeAreaInsets.bottom - 96
        sheetTop = isExpanded ? expanded : collapsed
        framedBottom = sheetTop - PaeoniaSpacing.space8
        // The distance line's top, above the surface.
        let footerTop = sheetTop - PaeoniaSpacing.space32
        framedTop = if isNear {
            // Puts the middle of the framed area halfway between the Dynamic Island and the
            // distance line, where the avatars land when the couple is close.
            topInset + footerTop - framedBottom
        } else {
            // Room above the higher avatar for its note bubble.
            topInset + 56
        }
    }

    var framedHeight: CGFloat { framedBottom - framedTop }
}

/// Keeps a view still on screen while the scroll view's content moves under it.
private extension View {
    func pinnedInScroll() -> some View {
        visualEffect { content, proxy in
            content.offset(y: -proxy.frame(in: .scrollView(axis: .vertical)).minY)
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

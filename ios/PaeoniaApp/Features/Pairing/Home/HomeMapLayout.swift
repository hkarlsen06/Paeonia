import MapKit
import SwiftUI

/// PROTOTYPE. Home with the couple's live map behind everything. Both avatars sit on the
/// map with their stories and notes, and the rest of Home is one surface that scrolls up
/// over the map. A tap on the map, or a pull down past the top, opens the map full screen.
struct HomeMapLayout<Header: View, Sheet: View>: View {
    let current: LocationPoint
    let partner: LocationPoint
    let currentName: String
    let currentPhotoAssetID: UUID?
    let partnerName: String
    let partnerPhotoAssetID: UUID?
    let stories: StoriesViewModel?
    let storyPeople: StoryPeople?
    @ViewBuilder let header: Header
    @ViewBuilder let sheet: Sheet

    @AppStorage("proto.home.avatarSize") private var avatarSize: Double = 72
    @AppStorage("proto.home.fakePartner") private var fakePartner: FakePartnerPlace = .real
    @State private var camera: MapCameraPosition = .automatic
    @State private var avatarPoints: AvatarPoints?
    @State private var scroll = ScrollState()
    @State private var isMapOpen = UserDefaults.standard.bool(forKey: "proto.home.startExpanded")
    /// Only a drag that starts with Home at the top opens the map, so scrolling back up
    /// past the top doesn't.
    @State private var dragStartedAtTop = false
    @Namespace private var zoom

    private static var openPull: CGFloat { 100 }
    private static var sheetCorner: CGFloat { 32 }
    private static var zoomID: String { "homeMap" }

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
                    mapLayer(metrics)
                        .frame(height: metrics.sheetTop, alignment: .top)
                    sheetSurface(metrics)
                }
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectHidden(true, for: .top)
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: ScrollState.self) { geometry in
                ScrollState(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    visibleHeight: geometry.containerSize.height
                        - geometry.contentInsets.top - geometry.contentInsets.bottom
                )
            } action: { _, state in
                scroll = state
            }
            .onScrollPhaseChange { old, new in
                if new == .interacting, old != .interacting {
                    dragStartedAtTop = scroll.offset <= 1
                }
                if old == .interacting, dragStartedAtTop, -scroll.offset > Self.openPull {
                    isMapOpen = true
                }
            }
            // Backs the status bar once the surface reaches it, so cards never run under the clock.
            .overlay(alignment: .top) {
                Color.paeoniaBackgroundPrimary
                    .frame(height: metrics.topInset)
                    .opacity(scroll.offset >= metrics.sheetTop - metrics.topInset ? 1 : 0)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            .onChange(of: geo.size, initial: true) { frame(metrics) }
            .onChange(of: fakePartner) { frame(metrics) }
            .onChange(of: current) { frame(metrics) }
            .onChange(of: partner) { frame(metrics) }
            .fullScreenCover(isPresented: $isMapOpen) {
                HomeMapFullScreen(
                    current: current,
                    partner: partner,
                    currentName: currentName,
                    currentPhotoAssetID: currentPhotoAssetID,
                    partnerName: partnerName,
                    partnerPhotoAssetID: partnerPhotoAssetID
                )
                .navigationTransition(.zoom(sourceID: Self.zoomID, in: zoom))
            }
        }
    }

    private func frame(_ metrics: Metrics) {
        guard metrics.width > 0, metrics.framedHeight > 40 else { return }
        let region = CoupleMapFraming.region(
            current: current.coordinate,
            partner: partnerCoordinate,
            aspectRatio: metrics.width / metrics.framedHeight
        )
        camera = .region(region)
    }

    // MARK: Map

    private func mapLayer(_ metrics: Metrics) -> some View {
        ZStack(alignment: .top) {
            ZStack {
                Map(position: $camera, interactionModes: []) {}
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .environment(\.colorScheme, .dark)
                    .grayscale(1)
                    .colorMultiply(.paeoniaAccentPrimary)
                    .safeAreaPadding(.top, max(metrics.framedTop, 0))
                    // Also places the Apple Maps mark, on the line above the surface.
                    .safeAreaPadding(.bottom, max(metrics.fullHeight - metrics.framedBottom, 0))
                    .onMapCameraChange(frequency: .continuous) { context in
                        guard MapScreenPoint.isUsable(context.rect) else { return }
                        avatarPoints = AvatarPoints(
                            own: MapScreenPoint.point(current.coordinate, in: context.rect, box: metrics.framedBox),
                            partner: MapScreenPoint.point(partnerCoordinate, in: context.rect, box: metrics.framedBox)
                        )
                    }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isMapOpen = true }
                    .accessibilityAddTraits(.isButton)
                avatars
            }
            .frame(height: metrics.fullHeight)
            .matchedTransitionSource(id: Self.zoomID, in: zoom)
            .pinnedInScroll()

            header
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, metrics.topInset)
                .pinnedInScroll()
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
        // Fills the screen below the map when there are few cards, and no more, so the
        // scroll stops once the last card is in view.
        .frame(maxWidth: .infinity, minHeight: max(scroll.visibleHeight - metrics.sheetTop, 0), alignment: .top)
        // The surface's color runs on past its end, behind the tab bar and the scroll's
        // bottom bounce, so the map never shows below it.
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: Self.sheetCorner, topTrailingRadius: Self.sheetCorner)
                .fill(Color.paeoniaBackgroundPrimary)
                .padding(.bottom, -metrics.fullHeight)
                .shadow(color: .black.opacity(0.35), radius: 18, y: -6)
        }
        .overlay(alignment: .topTrailing) {
            HomeMapDistanceLine(current: current, partner: partner, partnerCoordinate: partnerCoordinate)
                .padding(.trailing, PaeoniaSpacing.space16)
                .offset(y: -PaeoniaSpacing.space32)
        }
    }
}

private struct ScrollState: Equatable {
    var offset: CGFloat = 0
    var visibleHeight: CGFloat = 0
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

    init(geo: GeometryProxy, isNear: Bool) {
        width = geo.size.width
        topInset = geo.safeAreaInsets.top
        fullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
        sheetTop = topInset + 236
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
    /// Where the map's visible rect sits on screen: inside its safe-area padding.
    var framedBox: CGRect { CGRect(x: 0, y: framedTop, width: width, height: framedHeight) }
}

/// Keeps a view still on screen while the scroll view's content moves under it.
private extension View {
    func pinnedInScroll() -> some View {
        visualEffect { content, proxy in
            content.offset(y: -proxy.frame(in: .scrollView(axis: .vertical)).minY)
        }
    }
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

/// "Sammen · 2 t" or "306 km · 2 t", on the line above the surface.
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

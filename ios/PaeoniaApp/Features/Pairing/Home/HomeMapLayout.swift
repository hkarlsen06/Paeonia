import CoreLocation
import SwiftUI

/// Home with the couple's map as its header. The map fades on behind the cards,
/// both avatars sit on it with their stories and notes, and the cards follow in one plain
/// scroll view. The mark and the streak stay at the top in a bar that turns to glass once
/// the cards scroll under it, like a navigation bar. Without both locations, the avatars
/// sit in a row instead, with why there is no map below them and the world faintly behind
/// them. That is the same map, so it flies in from the world once both places arrive.
///
/// One view covers both, so the stories strip keeps its place when the map comes or goes,
/// and a story or note the person is writing stays open.
struct HomeMapLayout<Header: View, Sheet: View, Footer: View>: View {
    let mapState: CoupleMapState
    let partnerName: String
    let stories: StoriesViewModel?
    let storyPeople: StoryPeople?
    let hearts: HeartsViewModel?
    let mapTiles: HomeMapTileStatus
    let onPromptCurrentLocation: () -> Void
    let onRefresh: () async -> Void
    /// The bar's row, which places the map's title between its buttons.
    @ViewBuilder let header: (AnyView) -> Header
    @ViewBuilder let sheet: Sheet
    @ViewBuilder let footer: Footer

    let avatarSize: Double = 72
    /// The kind of notice the person said "Not now" to. It shows again once the reason
    /// for having no map changes.
    @AppStorage("home.locationNotice.dismissed") private var dismissedNotice = ""
    @Environment(\.avatarStyling) var avatarStyling
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.launchContentRevealed) private var launchContentRevealed
    @Environment(LaunchMapFlight.self) private var launchMapFlight: LaunchMapFlight?
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrollOffset: CGFloat = 0
    @State var topBarHeight = Self.headerHeight
    @State var compass = PartnerCompass()
    @State private var flights = HeartFlights()
    @State private var heartTaps = 0
    /// Changes on every frame the camera moves, so only the views that place things on the
    /// map read it, not this body.
    @State private var camera = HomeMapCamera()
    @State private var mapLocations: HomeMapLocations?
    @State var markerMeasurements = StoryMarkerMeasurements()
    @State var explorer = HomeMapExplorer()
    @State var isShowingMapDetails = false
    @State private var isNoteOpen = false
    /// Where the cards start, in the page's coordinates, so the world preview fades out above them.
    @State private var cardsTop: CGFloat = 0
    /// The map showed the world before the couple arrived, so it fades in from there.
    @State var previewedMap = false

    /// Both places, while there is a map to show.
    private var couple: HomeMapCouple? {
        guard case let .ready(current, partner, wasStale) = mapState else { return nil }
        return HomeMapCouple(
            current: current,
            partner: partner,
            currentCoordinate: mapLocations?.current ?? current.coordinate,
            partnerCoordinate: mapLocations?.partner ?? partner.coordinate,
            partnerWasStaleAtLastRefresh: wasStale
        )
    }

    var body: some View {
        GeometryReader { geo in
            let couple = couple
            let screen = HomeMapScreen(geo: geo, additionalHeaderHeight: max(topBarHeight - Self.headerHeight, 0))
            // The first sizing pass has zero width, a sliver at the leading edge. Build the
            // page only once it has its real size. A scroll view that already exists would
            // otherwise grow out of that sliver, sliding in from the side, whenever an
            // animation runs at that moment.
            if screen.width > 0 {
                scrollPage(couple, screen)
            }
        }
        // A note's keyboard belongs to its clear cover, so Home's map and cards stay in place
        // behind it. No other keyboard is ignored. Ignoring one also drops the tab bar's inset,
        // and Home came back from a sheet's keyboard with that inset gone and its last cards
        // under the tab bar.
        .ignoresSafeArea(isNoteOpen ? .keyboard : [])
        .onPreferenceChange(HomeNoteIsOpenKey.self) { isNoteOpen = $0 }
        .onChange(of: mapState, initial: true) { _, _ in
            retainMapLocations()
            if showsMapPreview {
                previewedMap = true
            } else if mapState == .loading {
                previewedMap = false
            }
        }
        .sheet(isPresented: $isShowingMapDetails) {
            if let couple {
                LocationMapDetails(
                    current: couple.current, partner: couple.partner, partnerName: partnerName,
                    partnerWasStaleAtLastRefresh: couple.partnerWasStaleAtLastRefresh
                )
            }
        }
    }

    /// The page in its scroll view, with the bar above it.
    private func scrollPage(_ couple: HomeMapCouple?, _ screen: HomeMapScreen) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // The page ends at the top of the tab bar, so the footer's first card starts
                // level with the bar, as wide as it, and the card under it peeks up below.
                page(couple, screen)
                    .fixedSize(horizontal: false, vertical: true)
                footer
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, PaeoniaSpacing.space16)
            // A pinch can span the map and the cards below it.
            .homeMapGestures(explorer)
        }
        .scrollIndicators(.hidden)
        // Offline, the avatars move from where they wait for the map to their places.
        .animation(reduceMotion ? nil : PaeoniaMotion.homeLayoutChange, value: mapTiles.tiles)
        // The notice gives way to the map, and the cards move down under it.
        .animation(reduceMotion ? nil : PaeoniaMotion.homeLayoutChange, value: reservesMapSpace)
        .refreshable {
            await onRefresh()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
        }
        // When everything fits, there is nothing to scroll to, so the page stays still.
        .scrollBounceBehavior(.basedOnSize)
        // Keep the scroll view's bounds and insets stable as the map arrives.
        // Without a map, the page reserves the header's space itself.
        .ignoresSafeArea(edges: .top)
        // Like a navigation bar: no glass at rest over the map, glass as soon as Home scrolls.
        .scrollEdgeEffectHidden(scrollOffset <= 1, for: .top)
        .safeAreaBar(edge: .top) {
            topBar(couple)
        }
        .onChange(of: hearts?.incomingBurst) { _, burst in
            // Hearts fly between the avatars wherever they can be sent. Otherwise only the
            // line in the bar tells the person.
            if let burst, couple != nil || canSendHearts {
                flights.receive(count: burst.flyingCount)
            }
        }
    }

    /// The top and the cards, in the one scroll view.
    private func page(_ couple: HomeMapCouple?, _ screen: HomeMapScreen) -> some View {
        VStack(spacing: 0) {
            top(couple, screen)
            if !reservesMapSpace {
                noMapNotice
            }
            sheet
                // A pinch or rotation on today's envelope moves the map behind it.
                .environment(\.homeMapExplorer, couple == nil ? nil : explorer)
                // The cards keep their own height, so only the map takes up the rest of the
                // screen. A square tile sizes itself from the room it is offered, and would
                // otherwise split that room with the map and overflow under the tab bar.
                .fixedSize(horizontal: false, vertical: true)
                // Keep loading and loaded descendants in the same moving coordinate space.
                .geometryGroup()
                // The cards start just under the map's last full row, and the map fades on behind them.
                .padding(.top, reservesMapSpace ? -HomeMapMetrics.cardsOverlap : PaeoniaSpacing.space24)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(homeMapPageSpace)).minY } action: {
                    cardsTop = $0
                }
        }
        .coordinateSpace(.named(homeMapPageSpace))
        // ScrollView also asks for an ideal width. Keep that probe at the viewport width,
        // so the square tiles never start narrow and animate out of their first positions.
        .frame(width: screen.width)
        // With the map, the page fills the screen down to the top of the tab bar, and
        // the map takes whatever the cards leave. One layout pass sizes both, so they
        // move together when a card changes height. A tall card makes the page longer
        // by most of its height, so it pushes the cards under it down instead of
        // shrinking the map.
        .modifier(HomeMapPageHeight(minHeight: reservesMapSpace ? screen.fillHeight : nil))
    }

    // MARK: Top

    /// The map with both avatars on it, or the avatars in a row. The stories strip is the
    /// same view in both, in the same place. Everything on the map reads the map's height
    /// from the layout, in the same pass that sizes the cards.
    private func top(_ couple: HomeMapCouple?, _ screen: HomeMapScreen) -> some View {
        ZStack(alignment: .top) {
            if couple != nil || showsMapPreview {
                mapBand(couple, screen)
            }

            storiesStrip(couple, screen)

            if let couple {
                heartLayer(couple, screen)
                    // Takes over from the row's heart in the same spot.
                    .transition(.identity)
                showBothButton(couple, screen)
            }
        }
        .frame(
            // Reserve the width while empty, so the arriving map cannot expand from the center.
            maxWidth: .infinity,
            minHeight: reservesMapSpace ? shortestBand(screen) : nil,
            maxHeight: reservesMapSpace ? .infinity : nil,
            alignment: .top
        )
        // A pull down keeps the map against the top of the screen.
        .visualEffect { [pinned = reservesMapSpace] content, proxy in
            content.offset(y: pinned ? min(0, -proxy.frame(in: .scrollView(axis: .vertical)).minY) : 0)
        }
    }

    /// The heart between the avatars when they sit together, and the hearts flying between them.
    private func heartLayer(_ couple: HomeMapCouple, _ screen: HomeMapScreen) -> some View {
        HomeMapBand { bandHeight in
            let metrics = metrics(couple, screen, bandHeight: bandHeight)
            let points = points(couple, metrics)
            let heartOpacity = couple.isNear ? 1 : rowHeartFade
            if heartOpacity > 0, hearts != nil {
                let middle = CGPoint(x: (points.own.x + points.partner.x) / 2, y: (points.own.y + points.partner.y) / 2)
                togetherHeart
                    .opacity(metrics.avatarOpacity(at: middle) * heartOpacity)
                    .position(middle)
                    .allowsHitTesting(couple.isNear)
            }
            KissLayer(start: points.own, end: points.partner, tapKisses: flights.kisses)
                .allowsHitTesting(false)
        }
    }

    /// Keep story controls available before location resolves, in the space reserved for the map.
    @ViewBuilder
    private func storiesStrip(_ couple: HomeMapCouple?, _ screen: HomeMapScreen) -> some View {
        if let stories, let storyPeople {
            HomeStoriesStrip(
                viewModel: stories,
                people: storyPeople,
                avatarSize: reservesMapSpace ? avatarSize : Self.rowAvatarSize,
                arrange: reservesMapSpace ? { own, partner in
                    AnyView(
                        HomeMapBand { bandHeight in
                            let metrics = metrics(couple, screen, bandHeight: bandHeight)
                            let points = points(couple, metrics)
                            let scale = avatarScale
                            own.scaleEffect(scale).opacity(metrics.avatarOpacity(at: points.own))
                                .position(points.own)
                            partner.scaleEffect(scale).opacity(metrics.avatarOpacity(at: points.partner))
                                .position(points.partner)
                        }
                    )
                } : nil,
                middle: !reservesMapSpace && hearts != nil && canSendHearts ? AnyView(rowHeart) : nil,
                middleOverlap: Self.heartOverlap,
                onMarkerMeasurements: { markerMeasurements = $0 }
            )
            // The row sits below the bar. The map, and the avatars on it, start at the top of
            // the screen, so the map stays put when it takes over from the row.
            .padding(.top, reservesMapSpace ? 0 : rowTop(screen))
            // The row and the map put the avatars in the same spots when the map arrives, so
            // they swap at once instead of fading across, and fly on with the map.
            .animation(nil, value: reservesMapSpace)
        }
    }

    func metrics(_ couple: HomeMapCouple?, _ screen: HomeMapScreen, bandHeight: CGFloat) -> HomeMapMetrics {
        HomeMapMetrics(
            screen: screen,
            bandHeight: max(bandHeight, shortestBand(screen)),
            avatarSize: avatarSize,
            isNear: couple?.isNear ?? true,
            markerMeasurements: markerMeasurements
        )
    }

    private func shortestBand(_ screen: HomeMapScreen) -> CGFloat {
        let pillBottom = screen.topInset + PaeoniaSpacing.compactButtonHeight + screen.additionalHeaderHeight
        return max(
            screen.shortestBand,
            pillBottom + PaeoniaSpacing.space8 + markerMeasurements.above
                + markerMeasurements.below + HomeMapMetrics.fadeHeight
        )
    }

    /// The map view's framing, with the avatars' places in the page's points.
    func framing(_ couple: HomeMapCouple, _ metrics: HomeMapMetrics) -> HomeMapLibreView.Framing {
        let screen = metrics.screen
        let framing = HomeMapLibreView.camera(
            current: couple.currentCoordinate, partner: couple.partnerCoordinate, isNear: couple.isNear,
            area: metrics.framedBox.offsetBy(dx: screen.mapBleed.width, dy: screen.mapBleed.height),
            viewSize: screen.mapViewSize
        )
        let points = HomeMapAvatarPoints(own: framing.own, partner: framing.partner).offsetBy(screen.pageOffset)
        return HomeMapLibreView.Framing(
            center: framing.center, zoom: framing.zoom, direction: framing.direction,
            own: points.own, partner: points.partner
        )
    }

    private func retainMapLocations() {
        guard case let .ready(current, partner, _) = mapState else {
            mapLocations = nil
            camera.projection = nil
            return
        }
        let latest = HomeMapLocations(
            current: current.coordinate,
            partner: partner.coordinate
        )
        mapLocations = mapLocations?.retainingNearbyLocations(from: latest) ?? latest
    }
}

extension HomeMapLayout {
    /// The map, faded into the cards, with the open map above them sending hearts. Without
    /// the couple, the world faintly behind the row of avatars and the notice.
    private func mapBand(_ couple: HomeMapCouple?, _ screen: HomeMapScreen) -> some View {
        HomeMapBand { bandHeight in
            let metrics = metrics(couple, screen, bandHeight: bandHeight)
            HomeMapLibreView(
                places: couple.map { places($0, metrics) },
                avatarSize: avatarSize,
                compass: compass,
                introSpots: couple.flatMap { introSpots($0, metrics) },
                // Home also mounts under the App Store's purchase sheet after a purchase.
                // The intro waits until nothing covers the app, so the person sees it.
                canStartIntro: launchContentRevealed && scenePhase == .active,
                launchFlight: launchMapFlight,
                explorer: explorer,
                tiles: mapTiles,
                onProjection: { [camera] projection in
                    let projection = projection.offsetBy(screen.pageOffset)
                    guard camera.projection != projection else { return }
                    camera.projection = projection
                }
            )
            // Always as tall as the map can get, so the map view never resizes while
            // the map grows or shrinks. Only the fade moves.
            .frame(width: screen.mapViewSize.width, height: screen.mapViewSize.height)
            .overlay(alignment: .top) { tabLight(screen) }
            .mask(alignment: .top) {
                // Without the couple, the world fades out above the cards.
                couple == nil
                    ? fadeMask(bottom: cardsTop + screen.mapBleed.height, fadeLength: cardsTop * 0.6)
                    : fadeMask(bottom: metrics.bandHeight + screen.mapBleed.height, fadeLength: metrics.fadeLength)
            }
            .padding(.horizontal, -screen.mapBleed.width)
            .padding(.top, -screen.mapBleed.height)
            .opacity(mapOpacity(couple))
            // The world preview only hints at the map to come.
            .accessibilityHidden(couple == nil)

            if couple != nil {
                mapControls(metrics)
            }
        }
    }

    private func places(_ couple: HomeMapCouple, _ metrics: HomeMapMetrics) -> HomeMapLibreView.Places {
        HomeMapLibreView.Places(
            current: couple.currentCoordinate,
            partner: couple.partnerCoordinate,
            isNear: couple.isNear,
            framedBox: metrics.framedBox.offsetBy(dx: metrics.screen.mapBleed.width, dy: metrics.screen.mapBleed.height)
        )
    }

    private func mapControls(_ metrics: HomeMapMetrics) -> some View {
        Group {
            // The faded map under the cards does nothing on a tap, but SwiftUI hands the
            // page's map gesture only touches that land on something. The areas over the map
            // decide whether a drag or a pinch from here moves it.
            Color.clear
                .contentShape(Rectangle())
                .accessibilityHidden(true)

            // A tap on the open map sends a heart, as on the map card. Only down to the
            // cards, so a tap between two cards does nothing.
            Color.clear
                .frame(height: metrics.framedBottom)
                .contentShape(Rectangle())
                .onTapGesture { sendHeart() }
                .homeMapArea("map", explorer)
                // VoiceOver sends hearts from the distance line in the bar.
                .accessibilityHidden(true)
        }
    }

    /// Where the row of avatars starts without a map, below the bar.
    func rowTop(_ screen: HomeMapScreen) -> CGFloat {
        screen.topInset + topBarHeight + PaeoniaSpacing.space8
    }

    func sendHeart() {
        guard let hearts else { return }
        flights.send()
        hearts.tap()
    }

    /// Eases out over a long stretch, so the map runs into the cards instead of ending.
    private func fadeMask(bottom: CGFloat, fadeLength: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.75), location: 0.15),
                    .init(color: .black.opacity(0.45), location: 0.35),
                    .init(color: .black.opacity(0.2), location: 0.6),
                    .init(color: .black.opacity(0.06), location: 0.82),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: max(fadeLength, 0))
        }
        .frame(height: max(bottom, 0))
    }

    var mapProjection: HomeMapProjection? { camera.projection }

    /// The other tabs' light from the top, drawn over the map so Home has it too. The map is
    /// darker than the plain background, so the light is stronger here to look the same. It
    /// stays put while the map scrolls away, like the light behind the cards. It covers the
    /// whole map view, past the screen's edges, so its frame grows by one scale both ways and
    /// its glows stay on the screen's top corners at their usual size.
    private func tabLight(_ screen: HomeMapScreen) -> some View {
        let bleed = screen.mapBleed
        let height = (screen.visibleBottom + screen.bottomInset) * PaeoniaTabLight.reach
        let frame = CGSize(width: screen.mapViewSize.width, height: height * screen.mapViewSize.width / screen.width)
        return PaeoniaTabLight(
            strength: 0.35,
            leadingCorner: UnitPoint(x: bleed.width / frame.width, y: bleed.height / frame.height),
            trailingCorner: UnitPoint(x: (bleed.width + screen.width) / frame.width, y: bleed.height / frame.height),
            radiusFraction: screen.width / frame.width
        )
        .frame(width: frame.width, height: frame.height)
        .visualEffect { content, proxy in
            content.offset(y: max(0, -proxy.frame(in: .scrollView(axis: .vertical)).minY - bleed.height))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var reservesMapSpace: Bool { mapState == .loading || couple != nil }

    /// Without both places, the world shows faintly behind the avatars as a hint of the map.
    /// Not once the relationship has ended, since no map will come.
    var showsMapPreview: Bool {
        !reservesMapSpace && mapState != .partnerUnknown(.relationshipEnded)
    }

    private static var headerHeight: CGFloat {
        PaeoniaSpacing.compactButtonHeight + PaeoniaSpacing.space12
    }

    /// The heart between the avatars in the row, with the hearts flying from one to the other.
    private var rowHeart: some View {
        let reach = (Self.rowAvatarSize + Self.heartWidth) / 2 - Self.heartOverlap
        return togetherHeart
            .overlay {
                KissLayer(
                    start: CGPoint(x: Self.rowAvatarSize / 2, y: Self.rowAvatarSize / 2),
                    end: CGPoint(x: Self.rowAvatarSize / 2 + 2 * reach, y: Self.rowAvatarSize / 2),
                    tapKisses: flights.kisses
                )
                .frame(width: Self.rowAvatarSize + 2 * reach, height: Self.rowAvatarSize)
                .allowsHitTesting(false)
            }
    }

    /// Side by side, the glossy heart sits in the gap between the two avatars and sends hearts.
    private var togetherHeart: some View {
        Button {
            heartTaps += 1
            GameSound.send.play()
            sendHeart()
        } label: {
            GlossyHeart(width: Self.heartWidth, tapCount: heartTaps)
                .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: heartTaps)
        .accessibilityLabel(Text(.heartsSendAction))
        .accessibilityHint(Text(.heartsSendHint(partnerName)))
    }

    static var heartWidth: CGFloat { 44 }
    /// How far the heart reaches over each avatar.
    static var heartOverlap: CGFloat { 4 }
    static var rowAvatarSize: CGFloat { 72 }

    // MARK: No map

    /// Why there is no map and what to do about it, with a line between it and the cards.
    @ViewBuilder
    private var noMapNotice: some View {
        if let notice = HomeMapNotice(
            state: mapState, partnerName: partnerName, onPromptCurrentLocation: onPromptCurrentLocation
        ), notice.id != dismissedNotice {
            HomeMapNoticeView(notice: notice) {
                withAnimation(reduceMotion ? nil : PaeoniaMotion.homeLayoutChange) {
                    dismissedNotice = notice.id
                }
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space24)
            .transition(.opacity)

            Rectangle()
                .fill(Color.paeoniaTextPrimary.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space24)
                .accessibilityHidden(true)
        }
    }

    /// Not while the map is still loading, and nobody receives hearts once the
    /// relationship has ended.
    var canSendHearts: Bool {
        switch mapState {
        case .loading, .partnerUnknown(.relationshipEnded): false
        default: true
        }
    }
}

/// The page's own coordinates, which start at the top of the screen.
private nonisolated let homeMapPageSpace = "HomeMapLayout.page"

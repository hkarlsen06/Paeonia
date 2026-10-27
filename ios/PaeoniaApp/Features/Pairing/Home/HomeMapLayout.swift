import CoreLocation
import SwiftUI

/// PROTOTYPE. Home with the couple's map as its header. The map fades on behind the cards,
/// both avatars sit on it with their stories and notes, and the cards follow in one plain
/// scroll view. The mark and the streak stay at the top in a bar that turns to glass once
/// the cards scroll under it, like a navigation bar. Without both locations, the avatars
/// sit in a row instead, with why there is no map below them.
///
/// One view covers both, so the stories strip keeps its place when the map comes or goes,
/// and a story or note the person is writing stays open.
struct HomeMapLayout<Header: View, Sheet: View>: View {
    let mapState: CoupleMapState
    let partnerName: String
    let stories: StoriesViewModel?
    let storyPeople: StoryPeople?
    let hearts: HeartsViewModel?
    let onPromptCurrentLocation: () -> Void
    let onRefresh: () async -> Void
    @ViewBuilder let header: Header
    @ViewBuilder let sheet: Sheet

    @AppStorage("proto.home.avatarSize") private var avatarSize: Double = 72
    @AppStorage("proto.home.fakePartner") private var fakePartner: FakePartnerPlace = .real
    /// The kind of notice the person said "Not now" to. It shows again once the reason
    /// for having no map changes.
    @AppStorage("home.locationNotice.dismissed") private var dismissedNotice = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollOffset: CGFloat = 0
    @State private var compass = PartnerCompass()
    @State private var flights = HeartFlights()
    @State private var heartTaps = 0
    @State private var mapProjection: HomeMapProjection?
    @State private var mapLocations: HomeMapLocations?

    /// Both places, while there is a map to show.
    private var couple: HomeMapCouple? {
        guard case let .ready(current, partner, wasStale) = mapState else { return nil }
        return HomeMapCouple(
            current: current,
            partner: partner,
            currentCoordinate: mapLocations?.current ?? current.coordinate,
            partnerCoordinate: mapLocations?.partner ?? fakePartner.coordinate ?? partner.coordinate,
            partnerWasStaleAtLastRefresh: wasStale
        )
    }

    var body: some View {
        GeometryReader { geo in
            let couple = couple
            let screen = HomeMapScreen(geo: geo)
            ScrollView {
                page(couple, screen)
            }
            .scrollIndicators(.hidden)
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
                header
                    .frame(height: PaeoniaSpacing.compactButtonHeight)
                    // Sits where a navigation bar puts its title, under the Dynamic Island.
                    .overlay { title(couple) }
                    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                    // Leave room below the pill for the bar's glass.
                    .padding(.bottom, PaeoniaSpacing.space12)
            }
            .onChange(of: hearts?.incomingBurst) { _, burst in
                // Hearts fly between the avatars wherever they can be sent. Otherwise only the
                // line in the bar tells the person.
                if let burst, couple != nil || canSendHearts {
                    flights.receive(count: burst.flyingCount)
                }
            }
        }
        // A note's keyboard belongs to its cover. Keep Home's map and cards in place behind it.
        .ignoresSafeArea(.keyboard)
        .onChange(of: mapState, initial: true) { _, _ in retainMapLocations() }
        .onChange(of: fakePartner) { _, _ in
            mapLocations = nil
            retainMapLocations()
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
                // The cards keep their own height, so only the map takes up the rest of the
                // screen. A square tile sizes itself from the room it is offered, and would
                // otherwise split that room with the map and overflow under the tab bar.
                .fixedSize(horizontal: false, vertical: true)
                // Keep loading and loaded descendants in the same moving coordinate space.
                .geometryGroup()
                // The cards start just under the map's last full row, and the map fades on behind them.
                .padding(.top, reservesMapSpace ? -HomeMapMetrics.cardsOverlap : PaeoniaSpacing.space24)
        }
        .padding(.top, reservesMapSpace ? 0 : screen.topInset + Self.headerHeight + PaeoniaSpacing.space8)
        // With the map, the page fills the screen down to just above the tab bar, and
        // the map takes whatever the cards leave. One layout pass sizes both, so they
        // move together when a card changes height.
        .frame(minHeight: reservesMapSpace ? screen.fillHeight : nil, alignment: .top)
    }

    /// The partner's hearts while they play, otherwise how far apart the couple is.
    @ViewBuilder
    private func title(_ couple: HomeMapCouple?) -> some View {
        ZStack {
            if let line = hearts?.incomingLine {
                HeartsIncomingLine(text: line)
                    .lineLimit(1)
                    .transition(.opacity)
            } else if let couple {
                HomeMapDistanceLine(
                    current: couple.current,
                    partner: couple.partner,
                    partnerCoordinate: fakePartner.coordinate ?? couple.partner.coordinate,
                    partnerWasStaleAtLastRefresh: couple.partnerWasStaleAtLastRefresh,
                    compass: compass
                )
                .accessibilityAction(named: Text(.heartsSendAction)) { sendHeart() }
                .contextMenu { prototypeMenu }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: hearts?.incomingLine)
    }

    // MARK: Top

    /// The map with both avatars on it, or the avatars in a row. The stories strip is the
    /// same view in both, in the same place. Everything on the map reads the map's height
    /// from the layout, in the same pass that sizes the cards.
    private func top(_ couple: HomeMapCouple?, _ screen: HomeMapScreen) -> some View {
        ZStack(alignment: .top) {
            if let couple {
                mapBand(couple, screen)
            }

            storiesStrip(couple, screen)

            if let couple {
                heartLayer(couple, screen)
            }
        }
        .frame(
            // Reserve the width while empty, so the arriving map cannot expand from the center.
            maxWidth: .infinity,
            minHeight: reservesMapSpace ? screen.shortestBand : nil,
            maxHeight: reservesMapSpace ? .infinity : nil,
            alignment: .top
        )
        // A pull down keeps the map against the top of the screen.
        .visualEffect { [pinned = reservesMapSpace] content, proxy in
            content.offset(y: pinned ? min(0, -proxy.frame(in: .scrollView(axis: .vertical)).minY) : 0)
        }
    }

    /// The map, faded into the cards, with the open map above them sending hearts.
    private func mapBand(_ couple: HomeMapCouple, _ screen: HomeMapScreen) -> some View {
        GeometryReader { band in
            let metrics = metrics(couple, screen, bandHeight: band.size.height)
            HomeMapLibreView(
                current: couple.currentCoordinate,
                partner: couple.partnerCoordinate,
                isNear: couple.isNear,
                framedBox: metrics.framedBox,
                avatarSize: avatarSize,
                compass: compass,
                onProjection: { projection in
                    guard mapProjection != projection else { return }
                    mapProjection = projection
                }
            )
            // Always as tall as the map can get, so the map view never resizes while
            // the map grows or shrinks. Only the fade moves.
            .frame(height: screen.mapHeight)
            .mask(alignment: .top) { fadeMask(metrics) }

            // A tap on the open map sends a heart, as on the map card. Only down to the
            // cards, so a tap between two cards does nothing.
            Color.clear
                .frame(height: metrics.framedBottom)
                .contentShape(Rectangle())
                .onTapGesture { sendHeart() }
                // VoiceOver sends hearts from the distance line in the bar.
                .accessibilityHidden(true)
        }
    }

    /// The heart between the avatars when they sit together, and the hearts flying between them.
    private func heartLayer(_ couple: HomeMapCouple, _ screen: HomeMapScreen) -> some View {
        GeometryReader { band in
            let points = points(couple, metrics(couple, screen, bandHeight: band.size.height))
            if couple.isNear, hearts != nil {
                togetherHeart
                    .position(
                        x: (points.own.x + points.partner.x) / 2,
                        y: (points.own.y + points.partner.y) / 2
                    )
            }
            KissLayer(start: points.own, end: points.partner, tapKisses: flights.kisses)
                .allowsHitTesting(false)
        }
        .transaction { $0.animation = nil }
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
                        GeometryReader { band in
                            let points = points(couple, metrics(couple, screen, bandHeight: band.size.height))
                            own.position(points.own)
                            partner.position(points.partner)
                        }
                        .transaction { $0.animation = nil }
                    )
                } : nil,
                middle: !reservesMapSpace && hearts != nil && canSendHearts ? AnyView(rowHeart) : nil,
                middleOverlap: Self.heartOverlap
            )
        }
    }

    private func metrics(_ couple: HomeMapCouple?, _ screen: HomeMapScreen, bandHeight: CGFloat) -> HomeMapMetrics {
        HomeMapMetrics(
            screen: screen,
            bandHeight: max(bandHeight, screen.shortestBand),
            avatarSize: avatarSize,
            isNear: couple?.isNear ?? true
        )
    }

    /// Follow the camera's current projection instead of animating to its destination.
    /// Before its first frame, use the same math that places the map.
    private func points(_ couple: HomeMapCouple?, _ metrics: HomeMapMetrics) -> HomeMapAvatarPoints {
        let raw: HomeMapAvatarPoints
        if couple != nil, let mapProjection {
            raw = HomeMapAvatarPoints(own: mapProjection.own, partner: mapProjection.partner)
        } else if let couple {
            let framing = framing(couple, metrics)
            raw = HomeMapAvatarPoints(own: framing.own, partner: framing.partner)
        } else {
            let center = CGPoint(x: metrics.framedBox.midX, y: metrics.framedBox.midY)
            raw = HomeMapAvatarPoints(own: center, partner: center)
        }
        return kept(separated(raw, isNear: couple?.isNear ?? true), inside: metrics.avatarBounds)
    }

    private func framing(_ couple: HomeMapCouple, _ metrics: HomeMapMetrics) -> HomeMapLibreView.Framing {
        HomeMapLibreView.camera(
            current: couple.currentCoordinate,
            partner: couple.partnerCoordinate,
            isNear: couple.isNear,
            area: metrics.framedBox,
            viewSize: CGSize(width: metrics.width, height: metrics.screen.mapHeight)
        )
    }

    private func retainMapLocations() {
        guard case let .ready(current, partner, _) = mapState else {
            mapLocations = nil
            mapProjection = nil
            return
        }
        let latest = HomeMapLocations(
            current: current.coordinate,
            partner: fakePartner.coordinate ?? partner.coordinate
        )
        mapLocations = mapLocations?.retainingNearbyLocations(from: latest) ?? latest
    }

    private func sendHeart() {
        guard let hearts else { return }
        flights.send()
        hearts.tap()
    }

    /// Eases out over a long stretch, so the map runs into the cards instead of ending.
    private func fadeMask(_ metrics: HomeMapMetrics) -> some View {
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
            .frame(height: metrics.fadeLength)
        }
        .frame(height: metrics.bandHeight)
    }
}

extension HomeMapLayout {
    private var reservesMapSpace: Bool { mapState == .loading || couple != nil }

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
            GameSound.send.play(volume: 0.5)
            sendHeart()
        } label: {
            GlossyHeart(width: Self.heartWidth, tapCount: heartTaps)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: heartTaps)
        .accessibilityLabel(Text(.heartsSendAction))
        .accessibilityHint(Text(.heartsSendHint(partnerName)))
    }

    private static var heartWidth: CGFloat { 44 }
    /// How far the heart reaches over each avatar.
    private static var heartOverlap: CGFloat { 4 }
    private static var rowAvatarSize: CGFloat { 72 }

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
    private var canSendHearts: Bool {
        switch mapState {
        case .loading, .partnerUnknown(.relationshipEnded): false
        default: true
        }
    }

    // MARK: Avatars

    /// Holds each avatar inside the open map. Only a couple on opposite sides of the world
    /// can be too far apart for the widest zoom, and then an avatar waits at the edge, on
    /// the side its partner is.
    private func kept(_ points: HomeMapAvatarPoints, inside bounds: CGRect) -> HomeMapAvatarPoints {
        func keep(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        }
        return HomeMapAvatarPoints(own: keep(points.own), partner: keep(points.partner))
    }

    private func separated(_ points: HomeMapAvatarPoints, isNear: Bool) -> HomeMapAvatarPoints {
        // Wide enough that the two note bubbles never touch.
        let minimum = max(StoryNoteBubble.maxWidth + PaeoniaSpacing.space8, avatarSize + PaeoniaSpacing.space16)
        guard isNear else {
            // Apart: pushed away from each other along the line between the two places,
            // so north stays north, with room for a note bubble when one sits above the other.
            let apart = max(minimum, avatarSize + 56)
            let (own, partner) = CoupleMapFraming.separated(points.own, points.partner, minimumDistance: apart)
            return HomeMapAvatarPoints(own: own, partner: partner)
        }
        // Together: side by side around the midpoint, you on the left, with room for the heart between.
        let together = max(minimum, avatarSize + Self.heartWidth - 2 * Self.heartOverlap)
        let mid = CGPoint(x: (points.own.x + points.partner.x) / 2, y: (points.own.y + points.partner.y) / 2)
        return HomeMapAvatarPoints(
            own: CGPoint(x: mid.x - together / 2, y: mid.y),
            partner: CGPoint(x: mid.x + together / 2, y: mid.y)
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

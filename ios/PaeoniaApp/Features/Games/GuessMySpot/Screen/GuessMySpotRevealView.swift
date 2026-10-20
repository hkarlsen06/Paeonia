import MapKit
import SwiftUI

/// The reveal of a guessed round. The guesser's runs from the guess to where the
/// photo was taken, and the sender's the other way, from the real spot to the
/// partner's guess, so each partner finds out where the other one was.
/// The photo slides away and the map fills the screen. The first pin pulses, the
/// camera zooms out, a gold line draws to the other spot, its pin drops at the line's
/// end, and the camera flies down close to it while the distance counts up. Then the verdict
/// lands and the photo comes back with the place and the date. A guess still on its
/// way holds the first frame until the server answers with the real spot.
struct GuessMySpotRevealView: View {
    @Bindable var viewModel: GuessMySpotViewModel

    @State private var timeline = GuessMySpotRevealTimeline()
    @State private var camera: MapCameraPosition = GuessMySpotCamera.world
    @State private var cardHeight: CGFloat = 0
    /// The whole map on the screen, under the top room and the card too.
    @State private var mapFrame: CGRect = .zero
    /// The safe area under the map, which the map draws on through. See `GuessMySpotMap.drawnFrame`.
    @State private var bottomInset: CGFloat?
    /// The safe area over the map, under the top bar, which MapKit's own view reaches up into.
    @State private var topInset: CGFloat = 0
    @State private var hasPlacedCamera = false
    @State private var preloader = GuessMySpotMapPreloader()
    @State private var hasPreloaded = false
    /// Each flight's end, worked out once with its stops, so a flight starts without
    /// asking MapKit again and flies the exact views that were loaded.
    @State private var flightEnds: [GuessMySpotRevealTimeline.Camera: MapCameraPosition] = [:]
    /// The camera flight in progress, stepped once a frame.
    @State private var flight: Task<Void, Never>?
    /// Satellite for the whole reveal. Where its images are still loading, satellite
    /// shows a soft picture where the standard map shows gray, and a switch partway
    /// would drop the images the map has loaded. The settled map's button can turn it back.
    @State private var isSatellite = true
    /// The pin or pins the settled map shows, for the buttons beside the distance.
    @State private var focus: GuessMySpotRevealCameraButtons.Focus?
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var round: RemoteGuessMySpotRound? { viewModel.round }

    private var isHeld: Bool {
        viewModel.phase == .reveal(isHeld: true)
    }

    private var mapSize: CGSize { mapFrame.size }

    /// How tall the map draws, past its frame at the bottom.
    private var drawnHeight: CGFloat {
        GuessMySpotMap.drawnFrame(mapFrame, bottomInset: bottomInset ?? 0).height
    }

    /// A wide screen keeps the guess screen's columns: the photo and then the card
    /// on the left, and the camera frames the map to their right. The same test as
    /// `GuessMySpotSplitLayout`, so the reveal matches the screen before it.
    private var isWide: Bool {
        mapSize.width >= 700 && mapSize.width > mapSize.height
    }

    private var isSender: Bool {
        round?.senderUserID == viewModel.currentUserID
    }

    /// Where the reveal starts and where it lands.
    private var ends: (from: GuessMySpotCoordinate, to: GuessMySpotCoordinate)? {
        guard let guess = round?.guess, let spot = round?.spot else { return nil }
        return isSender ? (spot, guess) : (guess, spot)
    }

    private var plan: GuessMySpotRevealPlan? {
        guard let distance = round?.knownDistance else { return nil }
        return GuessMySpotRevealPlan(
            verdict: GuessMySpotRules.verdict(distanceMeters: distance),
            distanceMeters: distance,
            points: round?.knownPoints ?? GuessMySpotRules.points(distanceMeters: distance)
        )
    }

    var body: some View {
        // A tap anywhere skips to the settled result. It is a shortcut, and the buttons stay.
        // swiftlint:disable:next accessibility_trait_for_button
        ZStack(alignment: .top) {
            map
            GuessMySpotRevealPhoto(image: viewModel.roundPhoto, isAway: timeline.photoAway, isWide: isWide)
            distanceCapsule
        }
        .overlay(alignment: .bottom) {
            card
        }
        .overlay {
            // Over the whole screen, so the petals are not clipped to the card.
            if let start = timeline.bloomStart {
                GamePetalBloom(
                    start: start,
                    seed: round?.id.uuidString ?? "",
                    origin: bloomOrigin,
                    intensity: 3
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .paeoniaBottomBar(spacing: 0) {
            actions
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.vertical, PaeoniaSpacing.space8)
                // Under the card, in its column on a wide screen.
                .frame(maxWidth: Self.cardColumn)
                .frame(maxWidth: .infinity, alignment: isWide ? .leading : .center)
        }
        .simultaneousGesture(TapGesture().onEnded {
            if timeline.canSkip { timeline.skip() }
        })
        .onAppear(perform: placeFirstCamera)
        .onChange(of: plan, initial: true) { beginIfNeeded() }
        .onChange(of: timeline.camera) { _, stage in moveCamera(to: stage) }
        // A tap can settle the reveal while the camera still flies down. It lands at once
        // then, so the flight never moves the map under the partner's own pan.
        .onChange(of: timeline.isSettled) { _, settled in
            guard settled else { return }
            moveCamera(to: timeline.camera)
            // Reduce Motion settles on both pins. Otherwise on the pin that dropped, the partner's.
            focus = timeline.camera == .overview ? .both : .partner
        }
        .onChange(of: camera.positionedByUser) { _, byUser in
            if byUser { focus = nil }
        }
        .onChange(of: timeline.verdict) { _, verdict in
            guard verdict != nil else { return }
            viewModel.revealSettled()
            announce()
            if UIAccessibility.isVoiceOverRunning { isTitleFocused = true }
        }
        .onDisappear {
            flight?.cancel()
            preloader.cancel()
            timeline.stop()
        }
        .accessibilityIdentifier("guessMySpot.reveal")
    }

    /// The map's room at the top for the distance capsule and for a pin's drop.
    static let topRoom: CGFloat = 110
    /// The settled map's room at the top for the camera buttons.
    static let buttonsRoom: CGFloat = 60
    /// The card's column on a wide screen, its side padding included.
    static let cardColumn: CGFloat = PaeoniaSpacing.focusedContentWidth

    // MARK: Timeline

    private func beginIfNeeded() {
        guard !timeline.hasBegun else { return }
        guard let plan, !isHeld else {
            timeline.hold()
            return
        }
        timeline.begin(plan, reduceMotion: reduceMotion)
        preloadIfReady()
    }

    /// The first frame, placed once the map has its size. On the guesser's phone:
    /// the guess map as they left it, lined up with where it sat, when the guess pin
    /// is in it and it shows less than a continent. Then the two maps match under the
    /// fade. Otherwise the guess at about 300 km across. On the sender's phone: their
    /// own pin, the real spot, at about 60 km across.
    private func placeFirstCamera() {
        guard !hasPlacedCamera, mapSize != .zero, let guess = round?.guess else { return }
        if isSender {
            guard let spot = round?.spot else { return }
            camera = framed(GuessMySpotCamera.around(spot, meters: 60_000))
        } else if let rect = viewModel.guessMapRect, let source = viewModel.guessMapFrame,
                  rect.width < MKMapSize.world.width * 40 / 360, rect.contains(MKMapPoint(guess.location)) {
            camera = GuessMySpotCamera.continuing(rect, from: source, to: mapFrame)
        } else {
            camera = framed(GuessMySpotCamera.around(guess, meters: 300_000))
        }
        hasPlacedCamera = true
    }

    /// The part of the map a camera move frames: under the top room and a pin's head,
    /// and clear of the card. The card's room is kept from the start, so nothing
    /// slides when it rises.
    private func framed(
        _ position: MapCameraPosition,
        keepsCardRoom: Bool = true,
        maxScale: Double = .infinity
    ) -> MapCameraPosition {
        let insets = EdgeInsets(
            top: Self.topRoom + GuessMySpotPin.headSize,
            leading: isWide ? Self.cardColumn : 0,
            bottom: isWide || !keepsCardRoom ? PaeoniaSpacing.space8 : cardHeight + PaeoniaSpacing.space8,
            trailing: 0
        )
        return GuessMySpotCamera.filling(position, size: mapSize, insets: insets, maxScale: maxScale)
    }

    // MARK: Map

    private var map: some View {
        GuessMySpotMap(
            position: $camera,
            pins: pins,
            line: line,
            isInteractive: timeline.isSettled,
            showsSatelliteButton: timeline.isSettled,
            accessibilityValue: .guessMySpotMapPinDropped,
            satellite: $isSatellite,
            // Only a map with realistic elevation draws the globe. See `GuessMySpotGlobe`.
            elevation: .realistic
        )
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: {
            bottomInset = $0
            preloadIfReady()
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: {
            mapFrame = $0
            placeFirstCamera()
            preloadIfReady()
        }
        .accessibilityHidden(!timeline.isSettled)
    }

    // MARK: Card

    @ViewBuilder
    private var card: some View {
        Group {
            if isHeld {
                if viewModel.isHeldOnPhone {
                    GuessMySpotHeldCard(viewModel: viewModel)
                }
            } else if let plan {
                GuessMySpotResultCard(
                    round: round,
                    plan: plan,
                    image: viewModel.roundPhoto,
                    isSender: isSender,
                    viewModel: viewModel,
                    countedPoints: timeline.countedPoints,
                    isTitleFocused: $isTitleFocused
                )
                    // A short fade under the rise, so the card lands rather than cuts in.
                    .opacity(timeline.cardShown ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: timeline.cardShown)
                    .offset(y: timeline.cardShown || reduceMotion ? 0 : 120)
                    // It has nothing to tap, so a pan or pinch on it moves the map under it.
                    .allowsHitTesting(false)
                    .accessibilityHidden(!timeline.cardShown)
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.bottom, PaeoniaSpacing.space8)
        .frame(maxWidth: Self.cardColumn)
        .frame(maxWidth: .infinity, alignment: isWide ? .leading : .center)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            cardHeight = $0
            preloadIfReady()
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        let isShown = (isHeld && viewModel.isHeldOnPhone) || timeline.actionsShown
        Button {
            viewModel.continueFromReveal()
        } label: {
            Text(isSender ? .guessMySpotHandoffContinue : .guessMySpotHandoffSend)
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown || reduceMotion ? 0 : 12)
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
        .accessibilityIdentifier("guessMySpot.reveal.continue")
    }
}

// MARK: Distance

extension GuessMySpotRevealView {
    @ViewBuilder
    private var distanceCapsule: some View {
        if timeline.distanceStep > 0, let plan {
            GuessMySpotDistanceCapsule(
                counted: timeline.countedDistance,
                final: plan.distanceMeters,
                scale: timeline.capsuleScale
            )
            .padding(.top, PaeoniaSpacing.space8)
            // Centered over the map the camera frames.
            .frame(maxWidth: .infinity)
            .padding(.leading, isWide ? Self.cardColumn : 0)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
        if timeline.isSettled {
            GuessMySpotRevealCameraButtons(
                myStyle: viewModel.myStyle,
                partnerStyle: viewModel.partnerStyle,
                partnerName: viewModel.partnerName,
                focus: focus,
                onSelect: show
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }

    /// Moves the settled map to a button's pin, or out to both pins.
    private func show(_ focus: GuessMySpotRevealCameraButtons.Focus) {
        guard let round, let guess = round.guess, let spot = round.spot else { return }
        let position: MapCameraPosition? = switch focus {
        case .both: settledOverview()
        // The real spot is the sender's pin.
        case .mine where isSender, .partner where !isSender:
            framed(GuessMySpotCamera.landing(on: spot, guess: guess))
        case .mine, .partner: framed(GuessMySpotCamera.landing(on: guess, guess: spot))
        }
        guard let position else { return }
        self.focus = focus
        flight?.cancel()
        // ponytail: MapKit's own animation, which may show gray squares on a long hop.
        // If it does, step the camera along GuessMySpotFlight as the reveal does.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 1)) { camera = position }
    }
}

// MARK: Camera flights and map images

extension GuessMySpotRevealView {
    /// The framed camera of each stage.
    private func target(for stage: GuessMySpotRevealTimeline.Camera) -> MapCameraPosition? {
        guard let ends else { return nil }
        let target: MapCameraPosition = switch stage {
        case .start: GuessMySpotCamera.around(ends.from, meters: 60_000)
        case .overview: GuessMySpotCamera.framing(ends.from, ends.to)
        case .landed: GuessMySpotCamera.landing(on: ends.to, guess: ends.from)
        }
        guard stage == .overview else { return framed(target) }
        // A far guess asks for more of the world than MapKit's flat map shows. Fly to
        // the view it really shows when that fits both spots, and to the globe when not.
        guard let asked = framed(target).rect else { return framed(target) }
        let widest = shown(asked)
        guard widest.width < asked.width * 0.99 else { return .rect(widest) }
        // The card rises only after the flight down, so a guess too far to fit over
        // its room may use it, and both pins show.
        if !isWide, let open = framed(target, keepsCardRoom: false).rect, shown(open).width >= open.width * 0.99 {
            return .rect(shown(open))
        }
        // Too far apart for any flat view: the globe. It needs every point it can get,
        // so a pin may stand anywhere it shows whole. The distance capsule comes later.
        return globe(top: GuessMySpotPin.height + PaeoniaSpacing.space8, bottom: mapSize.height - PaeoniaSpacing.space8)
    }

    /// Both pins once the card is up, in the room between the camera buttons and
    /// the card. The flight's overview may use the card's room, because the card
    /// rises only after it, so it would hide a pin here. A guess too far to fit
    /// shows on the globe in that room.
    private func settledOverview() -> MapCameraPosition? {
        guard let round, let guess = round.guess, let spot = round.spot else { return nil }
        let both = GuessMySpotCamera.framing(guess, spot, padding: 0.2)
        let insets = EdgeInsets(
            top: Self.buttonsRoom + GuessMySpotPin.height,
            leading: isWide ? Self.cardColumn : PaeoniaSpacing.space16,
            bottom: isWide ? PaeoniaSpacing.space8 : cardHeight + PaeoniaSpacing.space8,
            trailing: PaeoniaSpacing.space16
        )
        guard let asked = GuessMySpotCamera.filling(both, size: mapSize, insets: insets).rect else { return nil }
        let widest = shown(asked)
        guard widest.width < asked.width * 0.99 else { return .rect(widest) }
        return globe(top: insets.top, bottom: mapSize.height - insets.bottom)
    }

    /// Both ends on the globe, their pins between `top` and `bottom` of the map. See `GuessMySpotGlobe`.
    private func globe(top: CGFloat, bottom: CGFloat) -> MapCameraPosition? {
        guard let ends else { return nil }
        let below = max(0, drawnHeight - mapSize.height)
        let height = mapSize.height + topInset + below
        // MapKit's camera looks at the middle of its whole view, which reaches under the bars.
        let middle = height / 2 - topInset
        let room = GuessMySpotGlobe.Room(
            up: middle - top, down: bottom - middle, side: mapSize.width / 2 - PaeoniaSpacing.space24
        )
        return .camera(GuessMySpotGlobe.framing(ends.from, ends.to, height: height, room: room))
    }

    private func shown(_ rect: MKMapRect) -> MKMapRect {
        GuessMySpotFlight.shown(rect, size: mapSize, above: topInset, below: max(0, drawnHeight - mapSize.height))
    }

    /// Flies along `GuessMySpotFlight` instead of with a SwiftUI animation, which
    /// MapKit runs its own way. See `GuessMySpotFlight`.
    private func moveCamera(to stage: GuessMySpotRevealTimeline.Camera) {
        flight?.cancel()
        // Reduce Motion settles on both pins, with the card already up.
        if timeline.isSettled, stage == .overview, let overview = settledOverview() {
            camera = overview
            return
        }
        guard let target = flightEnds[stage] ?? target(for: stage) else { return }
        guard !reduceMotion, !timeline.isSettled, let path = path(from: camera, to: target) else {
            camera = target
            return
        }
        let duration = stage == .landed ? timeline.schedule.landDuration : timeline.schedule.zoomOutDuration
        flight = Task {
            let began = CACurrentMediaTime()
            while !Task.isCancelled {
                let time = await GuessMySpotFrameClock.nextFrame()
                guard !Task.isCancelled else { return }
                let fraction = min(1, max(0, time - began) / duration)
                guard fraction < 1 else { break }
                let eased = stage == .landed ? GuessMySpotFlight.easedDown(fraction) : GuessMySpotFlight.eased(fraction)
                camera = path(eased)
            }
            guard !Task.isCancelled else { return }
            camera = target
        }
    }

    /// Draws every stop of both flights off screen while the reveal builds up
    /// (`MKMapSnapshotter`), which puts their images in the phone's storage, from
    /// where the map reads them faster than over the network. The reveal never
    /// waits for them. The stops must be the exact views the camera passes, so
    /// this waits for the map's size and the card's height.
    private func preloadIfReady() {
        guard !hasPreloaded, !reduceMotion, timeline.hasBegun, !timeline.isSettled, timeline.camera == .start,
              hasPlacedCamera, mapSize != .zero, bottomInset != nil, isWide || cardHeight > 0,
              let start = camera.rect,
              let overview = target(for: .overview),
              let landing = target(for: .landed)
        else { return }
        hasPreloaded = true
        flightEnds = [.overview: overview, .landed: landing]
        let size = CGSize(width: mapSize.width, height: max(mapSize.height, drawnHeight))
        let overviewStops = stops(from: .rect(start), to: overview)
        let landingStops = stops(from: overview, to: landing)
        preloader.load(overviewStops.map(drawn), size: size, for: .overview)
        // The zoom out comes first and needs its images sooner, so the flight down waits its turn.
        Task { [preloader] in
            await preloader.wait(for: .overview, atMost: .seconds(1))
            preloader.load(landingStops.map(drawn), size: size, for: .landed)
        }
    }

    /// Where a flight from `start` to `end` is at each eased fraction: across the
    /// flat map, or as a camera when either end is on the globe.
    private func path(
        from start: MapCameraPosition,
        to end: MapCameraPosition
    ) -> ((Double) -> MapCameraPosition)? {
        if let start = start.rect, let end = end.rect {
            return { .rect(GuessMySpotFlight.view(from: start, to: end, at: $0)) }
        }
        guard let start = mapCamera(start), let end = mapCamera(end) else { return nil }
        return { .camera(GuessMySpotGlobe.view(from: start, to: end, at: $0)) }
    }

    /// The views to load ahead of a flight. See `GuessMySpotFlight.stops`.
    private func stops(from start: MapCameraPosition, to end: MapCameraPosition) -> [MapCameraPosition] {
        if let start = start.rect, let end = end.rect {
            return GuessMySpotFlight.stops(from: start, to: end).map { .rect($0) }
        }
        guard let start = mapCamera(start), let end = mapCamera(end) else { return [] }
        return GuessMySpotGlobe.stops(from: start, to: end).map { .camera($0) }
    }

    /// `position` as a camera, a part of the flat map as the camera that shows it.
    private func mapCamera(_ position: MapCameraPosition) -> MapCamera? {
        position.camera ?? position.rect.map {
            GuessMySpotGlobe.camera(
                showing: $0, size: mapSize, above: topInset, below: max(0, drawnHeight - mapSize.height)
            )
        }
    }

    /// `view` grown down to where the map draws, when it is a part of the flat map.
    private func drawn(_ view: MapCameraPosition) -> MapCameraPosition {
        view.rect.map { .rect(drawn($0)) } ?? view
    }

    /// `rect`, a camera's view of the map's frame, grown down to where the map draws.
    private func drawn(_ rect: MKMapRect) -> MKMapRect {
        let extra = max(0, drawnHeight - mapSize.height) * rect.width / max(1, mapSize.width)
        return MKMapRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + extra)
    }
}

// MARK: Verdict

extension GuessMySpotRevealView {
    /// Where the dropped pin stands on screen once the camera landed: the middle of the
    /// map the card leaves, above it or on a wide screen to its right.
    private var bloomOrigin: UnitPoint {
        guard mapSize.height > Self.topRoom, mapSize.width > Self.cardColumn else { return UnitPoint(x: 0.5, y: 0.3) }
        let framed = mapSize.height - Self.topRoom
        if isWide {
            return UnitPoint(
                x: (Self.cardColumn + (mapSize.width - Self.cardColumn) / 2) / mapSize.width,
                y: (Self.topRoom + framed / 2) / mapSize.height
            )
        }
        return UnitPoint(x: 0.5, y: (Self.topRoom + max(0, framed - cardHeight) / 2) / mapSize.height)
    }

    private func announce() {
        guard let plan else { return }
        let distance = GuessMySpotText.distance(plan.distanceMeters)
        let verdict = String(localized: GuessMySpotResultCard.title(
            for: plan.verdict,
            isSender: isSender,
            partnerName: viewModel.partnerName
        ))
            .trimmingCharacters(in: .punctuationCharacters)
        let points = GuessMySpotText.number(plan.points)
        var text = isSender
            ? String(localized: .guessMySpotRevealAnnouncementSender(viewModel.partnerName, distance, verdict, points))
            : String(localized: .guessMySpotRevealAnnouncementGuesser(distance, verdict, points))
        if let place = round?.placeName {
            text = String(localized: .guessMySpotRevealAnnouncementPlace(place)) + " " + text
        }
        AccessibilityNotification.Announcement(text).post()
    }
}

// MARK: Pins and line

extension GuessMySpotRevealView {
    /// The pin the reveal starts from stands and pulses, and the other one drops.
    /// A held guess has only its own pin.
    private var pins: [GuessMySpotMap.Pin] {
        guard let round, let guess = round.guess else { return [] }
        let guessPin = GuessMySpotMap.Pin(
            id: "guess", coordinate: guess, style: viewModel.style(of: round.guesserUserID)
        )
        guard let spot = round.spot else { return [standing(guessPin)] }
        let spotPin = GuessMySpotMap.Pin(id: "spot", coordinate: spot, style: viewModel.style(of: round.senderUserID))
        let (first, second) = isSender ? (spotPin, guessPin) : (guessPin, spotPin)
        return timeline.dropped ? [standing(first), dropping(second)] : [standing(first)]
    }

    private func standing(_ pin: GuessMySpotMap.Pin) -> GuessMySpotMap.Pin {
        var pin = pin
        pin.glow = timeline.glow
        pin.scale = timeline.pulseScale * timeline.verdictScale
        return pin
    }

    private func dropping(_ pin: GuessMySpotMap.Pin) -> GuessMySpotMap.Pin {
        var pin = pin
        pin.glow = timeline.glow
        pin.scale = timeline.verdictScale
        pin.lift = timeline.dropLift
        pin.ring = timeline.ring
        return pin
    }

    private var line: GuessMySpotMap.Line? {
        guard let ends else { return nil }
        let progress = timeline.lineProgress
        guard progress > 0 else { return nil }
        // A far guess draws quiet and dashed from the start, as in Consensio.
        return GuessMySpotMap.Line(from: ends.from, to: ends.to, progress: progress, isFar: plan?.verdict == .far)
    }
}

import MapKit
import SwiftUI

/// The reveal of a guessed round, from the guess to where the photo was taken.
/// The photo slides away and the map fills the screen. The guess pin pulses, the
/// camera zooms out, a gold line draws to the real spot, the real pin drops at its
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
    /// Where the camera is while it flies.
    @State private var flightPosition = GuessMySpotFlightPosition()
    /// Each flight's end, worked out once with its pictures, so a flight starts
    /// without asking MapKit again and flies the exact views that were drawn.
    @State private var flightEnds: [GuessMySpotRevealTimeline.Camera: MKMapRect] = [:]
    /// The zoom out's pictures over the map while it zooms out. See `GuessMySpotFlightBackdrop`.
    @State private var backdrop: GuessMySpotFlightBackdrop.Pictures?
    /// The camera flight in progress, stepped once a frame.
    @State private var flight: Task<Void, Never>?
    /// Starts as the guess screen's map, and turns to satellite once the real pin is planted.
    @State private var isSatellite = UserDefaults.standard.bool(forKey: GuessMySpotMap.satelliteKey)
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
        .onAppear(perform: placeCameraOnGuess)
        .onChange(of: plan, initial: true) { beginIfNeeded() }
        .onChange(of: timeline.camera) { _, stage in moveCamera(to: stage) }
        // A tap can settle the reveal while the camera still flies down. It lands at once
        // then, so the flight never moves the map under the partner's own pan.
        .onChange(of: timeline.isSettled) { _, settled in
            guard settled else { return }
            moveCamera(to: timeline.camera)
            // Reduce Motion settles on both pins. Otherwise on the real spot, the sender's pin.
            focus = timeline.camera == .overview ? .both : isSender ? .mine : .partner
        }
        .onChange(of: camera.positionedByUser) { _, byUser in
            if byUser { focus = nil }
        }
        // While the screen holds still, so the switch dissolves before the camera flies.
        .onChange(of: timeline.planted) { _, planted in
            if planted, !timeline.isSettled { turnSatellite() }
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
    /// The card's column on a wide screen, its side padding included.
    static let cardColumn: CGFloat = PaeoniaSpacing.focusedContentWidth

    // MARK: Timeline

    private func beginIfNeeded() {
        guard !timeline.hasBegun else { return }
        guard let plan, !isHeld else {
            timeline.hold()
            return
        }
        timeline.begin(plan, reduceMotion: reduceMotion) { [preloader] stage in
            // A slow connection holds the reveal on the planted pin a moment rather than fly over gray.
            await preloader.wait(for: stage, atMost: stage == .landed ? .seconds(2) : .seconds(1))
        }
        preloadIfReady()
    }

    /// The first frame, placed once the map has its size: the guess map as the
    /// guesser left it, lined up with where it sat, when the guess pin is in it and
    /// it shows less than a continent. Then the two maps match under the fade.
    /// Otherwise the guess at about 300 km across.
    private func placeCameraOnGuess() {
        guard !hasPlacedCamera, mapSize != .zero, let guess = round?.guess else { return }
        hasPlacedCamera = true
        if !isSender, let rect = viewModel.guessMapRect, let source = viewModel.guessMapFrame,
           rect.width < MKMapSize.world.width * 40 / 360, rect.contains(MKMapPoint(guess.location)) {
            camera = GuessMySpotCamera.continuing(rect, from: source, to: mapFrame)
        } else {
            camera = framed(GuessMySpotCamera.around(guess, meters: isSender ? 60_000 : 300_000))
        }
    }

    /// The part of the map a camera move frames: under the top room and a pin's head,
    /// and clear of the card. The card's room is kept from the start, so nothing
    /// slides when it rises.
    private func framed(_ position: MapCameraPosition, maxScale: Double = .infinity) -> MapCameraPosition {
        let insets = EdgeInsets(
            top: Self.topRoom + GuessMySpotPin.headSize,
            leading: isWide ? Self.cardColumn : 0,
            bottom: isWide ? PaeoniaSpacing.space8 : cardHeight + PaeoniaSpacing.space8,
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
            coversStyleSwitch: backdrop == nil
        )
        .overlay(alignment: .top) {
            if let backdrop {
                GuessMySpotFlightBackdrop(
                    pictures: backdrop,
                    position: flightPosition,
                    size: CGSize(width: mapSize.width, height: max(mapSize.height, drawnHeight)),
                    pins: pins,
                    line: line
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: {
            bottomInset = $0
            preloadIfReady()
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: {
            mapFrame = $0
            placeCameraOnGuess()
            preloadIfReady()
        }
        .accessibilityHidden(!timeline.isSettled)
    }

    private var pins: [GuessMySpotMap.Pin] {
        guard let round else { return [] }
        var pins: [GuessMySpotMap.Pin] = []
        if let guess = round.guess {
            pins.append(GuessMySpotMap.Pin(
                id: "guess",
                coordinate: guess,
                style: viewModel.style(of: round.guesserUserID),
                glow: timeline.glow,
                scale: timeline.pulseScale * timeline.verdictScale
            ))
        }
        if timeline.dropped, let spot = round.spot {
            pins.append(GuessMySpotMap.Pin(
                id: "spot",
                coordinate: spot,
                style: viewModel.style(of: round.senderUserID),
                glow: timeline.glow,
                scale: timeline.verdictScale,
                lift: timeline.dropLift,
                ring: timeline.ring
            ))
        }
        return pins
    }

    private var line: GuessMySpotMap.Line? {
        guard let round, let guess = round.guess, let spot = round.spot else { return nil }
        let progress = timeline.lineProgress
        guard progress > 0 else { return nil }
        // A far guess draws quiet and dashed from the start, as in Consensio.
        return GuessMySpotMap.Line(from: guess, to: spot, progress: progress, isFar: plan?.verdict == .far)
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
            .padding(.top, PaeoniaSpacing.space12)
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
        case .both: target(for: .overview)
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
        guard let round, let guess = round.guess, let spot = round.spot else { return nil }
        let target: MapCameraPosition = switch stage {
        case .guess: GuessMySpotCamera.around(guess, meters: 60_000)
        case .overview: GuessMySpotCamera.framing(guess, spot)
        case .landed: GuessMySpotCamera.landing(on: spot, guess: guess)
        }
        guard stage == .overview else { return framed(target) }
        // A far guess asks for more of the world than MapKit shows. Frame both spots
        // at MapKit's widest view instead, and fly to the view it really shows.
        guard let asked = framed(target).rect else { return framed(target) }
        let widest = shown(asked)
        guard widest.width < asked.width * 0.99 else { return .rect(widest) }
        guard let capped = framed(target, maxScale: widest.width / max(1, mapSize.width)).rect else {
            return .rect(widest)
        }
        return .rect(shown(capped))
    }

    private func shown(_ rect: MKMapRect) -> MKMapRect {
        GuessMySpotFlight.shown(rect, size: mapSize, above: topInset, below: max(0, drawnHeight - mapSize.height))
    }

    /// Flies along `GuessMySpotFlight` instead of with a SwiftUI animation, which
    /// MapKit runs its own way. See `GuessMySpotFlight`.
    private func moveCamera(to stage: GuessMySpotRevealTimeline.Camera) {
        flight?.cancel()
        flightPosition.rect = nil
        flightPosition.blur = 0
        backdrop = nil
        guard let target = flightEnds[stage].map(MapCameraPosition.rect) ?? target(for: stage) else { return }
        guard !reduceMotion, !timeline.isSettled, let start = camera.rect, let end = target.rect else {
            camera = target
            return
        }
        let duration = stage == .landed ? timeline.schedule.landDuration : timeline.schedule.zoomOutDuration
        // Every view drawn: the flight is all pictures, and the map jumps to its end
        // under them, so it loads that one view for the whole flight. See `GuessMySpotFlightBackdrop`.
        let complete = preloader.complete(stage)
        let isPictures = complete != nil
        if let pictures = complete {
            backdrop = GuessMySpotFlightBackdrop.Pictures(pictures: pictures, loaded: nil)
            flightPosition.rect = start
            // MapKit drops a camera move made in the same update as a style switch.
            if isSatellite || stage == .overview {
                camera = target
            } else {
                isSatellite = true
            }
        } else if stage == .overview, let pictures = preloader.pictures[.overview], !pictures.isEmpty {
            backdrop = GuessMySpotFlightBackdrop.Pictures(
                pictures: pictures.sorted { $0.rect.width > $1.rect.width }, loaded: drawn(start)
            )
            flightPosition.blur = 4
        }
        flight = Task { await fly(stage, from: start, to: target, duration: duration, isPictures: isPictures) }
    }

    /// Steps a flight once a frame: the map's camera, or over pictures only the
    /// backdrop. Then the pictures fade over the map, and are let go.
    private func fly(
        _ stage: GuessMySpotRevealTimeline.Camera,
        from start: MKMapRect,
        to target: MapCameraPosition,
        duration: TimeInterval,
        isPictures: Bool
    ) async {
        guard let end = target.rect else { return }
        let began = CACurrentMediaTime()
        while !Task.isCancelled {
            let time = await GuessMySpotFrameClock.nextFrame()
            guard !Task.isCancelled else { return }
            let fraction = min(1, max(0, time - began) / duration)
            guard fraction < 1 else { break }
            let eased = stage == .landed ? GuessMySpotFlight.easedDown(fraction) : GuessMySpotFlight.eased(fraction)
            let rect = GuessMySpotFlight.view(from: start, to: end, at: eased)
            if isPictures {
                if !MKMapRectEqualToRect(camera.rect ?? .null, end) { camera = target }
                // Soft with speed, so the flight starts and lands sharp on the map.
                flightPosition.blur = 4 * sin(.pi * fraction)
            } else {
                camera = .rect(rect)
            }
            flightPosition.rect = rect
        }
        guard !Task.isCancelled else { return }
        camera = target
        guard backdrop != nil else { return }
        await fadeBackdrop(stage, at: GuessMySpotFlight.view(from: start, to: end, at: 1), isPictures: isPictures)
    }

    /// Fades the pictures over the map once a flight has ended, then lets them go.
    private func fadeBackdrop(_ stage: GuessMySpotRevealTimeline.Camera, at end: MKMapRect, isPictures: Bool) async {
        // The map's own images of the end view arrive about now. The line waits for this fade.
        flightPosition.rect = end
        if isPictures {
            flightPosition.blur = 0
            // The last picture is the view the map is loading. The flight down holds it while
            // the map finishes; the zoom out can't, because the line waits for its fade.
            if stage == .landed { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled else { return }
        }
        withAnimation(.easeOut(duration: 0.25)) { backdrop?.opacity = 0 }
        // Then the drawn pins a moment longer, while MapKit's own fade back in under them.
        try? await Task.sleep(for: .milliseconds(isPictures ? 550 : 250))
        guard !Task.isCancelled else { return }
        flightPosition.rect = nil
        backdrop = nil
        preloader.release(stage)
    }

    /// The map turns to satellite while the screen holds still. With every view of the
    /// flight down drawn, its first picture dissolves in over the map, which switches
    /// under it out of sight and without the picture of the window a switch costs.
    private func turnSatellite() {
        guard let pictures = preloader.complete(.landed), let start = camera.rect else {
            isSatellite = true
            return
        }
        flight?.cancel()
        flightPosition.rect = start
        flightPosition.blur = 0
        backdrop = GuessMySpotFlightBackdrop.Pictures(pictures: pictures, loaded: nil, opacity: 0)
        withAnimation(.easeInOut(duration: 0.2)) { backdrop?.opacity = 1 }
        flight = Task {
            // Before the flight down, so its camera move isn't made with the switch.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            isSatellite = true
        }
    }

    /// Draws every stop of both flights off screen while the reveal builds up: the
    /// zoom out in the map's style, and the flight down in satellite. It waits for
    /// the map's size and the card's height, because the stops must be the exact
    /// views the camera passes, at the same zoom.
    private func preloadIfReady() {
        guard !hasPreloaded, !reduceMotion, timeline.hasBegun, !timeline.isSettled, timeline.camera == .guess,
              hasPlacedCamera, mapSize != .zero, bottomInset != nil, isWide || cardHeight > 0,
              let start = camera.rect,
              let overview = target(for: .overview)?.rect,
              let landing = target(for: .landed)?.rect
        else { return }
        hasPreloaded = true
        flightEnds = [.overview: overview, .landed: landing]
        let size = CGSize(width: mapSize.width, height: max(mapSize.height, drawnHeight))
        // The overview first: its picture covers the zoom out. See `GuessMySpotFlightBackdrop`.
        preloader.load(
            GuessMySpotFlight.stops(from: start, to: overview).reversed().map(drawn), size: size,
            satellite: isSatellite, for: .overview
        )
        // The zoom out comes first and needs its pictures sooner, so the flight down waits its turn.
        let landingStops = GuessMySpotFlight.stops(from: overview, to: landing).map(drawn)
        Task { [preloader] in
            await preloader.wait(for: .overview, atMost: .seconds(1))
            preloader.load(landingStops, size: size, satellite: true, for: .landed)
        }
    }

    /// `rect`, a camera's view of the map's frame, grown down to where the map draws.
    private func drawn(_ rect: MKMapRect) -> MKMapRect {
        let extra = max(0, drawnHeight - mapSize.height) * rect.width / max(1, mapSize.width)
        return MKMapRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + extra)
    }
}

// MARK: Verdict

extension GuessMySpotRevealView {
    /// Where the real pin stands on screen once the camera landed: the middle of the
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
        let verdict = String(localized: GuessMySpotResultCard.title(for: plan.verdict))
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

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
    @State private var hasPlacedCamera = false
    /// Starts as the guess screen's map, and turns to satellite as the camera lands.
    @State private var isSatellite = UserDefaults.standard.bool(forKey: GuessMySpotMap.satelliteKey)
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var round: RemoteGuessMySpotRound? { viewModel.round }

    private var isHeld: Bool {
        viewModel.phase == .reveal(isHeld: true)
    }

    private var mapSize: CGSize { mapFrame.size }

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
            photo
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
        .onChange(of: timeline.verdict) { _, verdict in
            guard verdict != nil else { return }
            viewModel.revealSettled()
            announce()
            if UIAccessibility.isVoiceOverRunning { isTitleFocused = true }
        }
        .onDisappear { timeline.stop() }
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
        if !reduceMotion { loadLandingImages() }
        timeline.begin(plan, reduceMotion: reduceMotion)
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
    private func framed(_ position: MapCameraPosition) -> MapCameraPosition {
        let insets = EdgeInsets(
            top: Self.topRoom + GuessMySpotPin.headSize,
            leading: isWide ? Self.cardColumn : 0,
            bottom: isWide ? PaeoniaSpacing.space8 : cardHeight + PaeoniaSpacing.space8,
            trailing: 0
        )
        return GuessMySpotCamera.filling(position, size: mapSize, insets: insets)
    }

    private func moveCamera(to stage: GuessMySpotRevealTimeline.Camera) {
        guard let round, let guess = round.guess, let spot = round.spot else { return }
        let target: MapCameraPosition = switch stage {
        case .guess: GuessMySpotCamera.around(guess, meters: 60_000)
        case .overview: GuessMySpotCamera.framing(guess, spot)
        case .landed: GuessMySpotCamera.landing(on: spot, guess: guess)
        }
        let duration = stage == .landed ? timeline.schedule.landDuration : timeline.schedule.zoomOutDuration
        // From the start of the flight, so the photos load on the way down, when the map is already moving.
        if stage == .landed { isSatellite = true }
        if reduceMotion || timeline.isSettled {
            camera = framed(target)
        } else {
            withAnimation(.easeInOut(duration: duration)) { camera = framed(target) }
        }
    }

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

    // MARK: Map

    private var map: some View {
        GuessMySpotMap(
            position: $camera,
            pins: pins,
            line: line,
            isInteractive: timeline.isSettled,
            showsSatelliteButton: timeline.isSettled,
            accessibilityValue: .guessMySpotMapPinDropped,
            satellite: $isSatellite
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: {
            mapFrame = $0
            placeCameraOnGuess()
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
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
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

// MARK: Photo and distance

extension GuessMySpotRevealView {
    /// The photo where the guess screen had it, on top or on a wide screen on the
    /// left, until it slides away up or to the left.
    private var photo: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let slides = timeline.photoAway && !reduceMotion
            let padding = PaeoniaSpacing.screenHorizontalPadding
            let share = GuessMySpotPhotoPane.splitShare
            GuessMySpotPhotoPane(image: viewModel.roundPhoto)
                .frame(
                    width: isWide ? max(0, (size.width - 2 * padding - PaeoniaSpacing.space12) * share) : nil,
                    height: max(0, isWide
                        ? size.height - PaeoniaSpacing.space8 - PaeoniaSpacing.space12
                        : size.height * share - PaeoniaSpacing.space12)
                )
                .background(.paeoniaSurfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
                .padding(.horizontal, padding)
                .padding(.top, PaeoniaSpacing.space8)
                .offset(
                    x: slides && isWide ? -size.width / 2 - 40 : 0,
                    y: slides && !isWide ? -size.height / 2 - 40 : 0
                )
                .opacity(timeline.photoAway ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

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
    }
}

// MARK: Landing images

extension GuessMySpotRevealView {
    /// Draws the flight's satellite views off screen while the reveal builds up: both
    /// spots, halfway down and the landing. Their images are then on the phone when
    /// the camera passes, and the map doesn't go blank for a moment.
    func loadLandingImages() {
        guard let round, let guess = round.guess, let spot = round.spot else { return }
        let views = [
            GuessMySpotCamera.framing(guess, spot),
            GuessMySpotCamera.around(spot, meters: 60_000),
            GuessMySpotCamera.landing(on: spot, guess: guess),
        ]
        for view in views {
            let options = MKMapSnapshotter.Options()
            options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
            if let rect = view.rect {
                options.mapRect = rect
            } else if let region = view.region {
                options.region = region
            }
            options.size = mapSize == .zero ? CGSize(width: 400, height: 800) : mapSize
            let snapshotter = MKMapSnapshotter(options: options)
            // The closure keeps the snapshotter alive until it finishes.
            snapshotter.start { _, _ in _ = snapshotter }
        }
    }
}

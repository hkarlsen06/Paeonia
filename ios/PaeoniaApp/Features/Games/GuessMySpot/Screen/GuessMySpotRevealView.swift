import MapKit
import SwiftUI

/// The reveal of a guessed round, from the guess to where the photo was taken.
/// The photo slides away and the map fills the screen. The guess pin pulses, the
/// camera zooms out, a gold line draws to the real spot, the real pin drops at its
/// end, and the camera lands there while the distance counts up. Then the verdict
/// lands and the photo comes back with the place and the date. A guess still on its
/// way holds the first frame until the server answers with the real spot.
struct GuessMySpotRevealView: View {
    @Bindable var viewModel: GuessMySpotViewModel

    @State private var timeline = GuessMySpotRevealTimeline()
    @State private var camera: MapCameraPosition = GuessMySpotCamera.world
    @State private var cardHeight: CGFloat = 0
    @State private var mapSize: CGSize = .zero
    @State private var hasPlacedCamera = false
    @AccessibilityFocusState private var isTitleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var round: RemoteGuessMySpotRound? { viewModel.round }

    private var isHeld: Bool {
        viewModel.phase == .reveal(isHeld: true)
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
                .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
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

    // MARK: Timeline

    private func beginIfNeeded() {
        guard !timeline.hasBegun else { return }
        guard let plan, !isHeld else {
            timeline.hold()
            return
        }
        timeline.begin(plan, reduceMotion: reduceMotion)
    }

    /// The first frame: where the guesser left the map, when the guess pin is in it
    /// and it shows less than a continent, or else the guess at about 300 km across.
    private func placeCameraOnGuess() {
        guard !hasPlacedCamera, let guess = round?.guess else { return }
        hasPlacedCamera = true
        if !isSender, let region = viewModel.guessRegion,
           region.span.latitudeDelta < 30, region.span.longitudeDelta < 40,
           abs(region.center.latitude - guess.latitude) < region.span.latitudeDelta / 2,
           abs(region.center.longitude - guess.longitude) < region.span.longitudeDelta / 2 {
            withAnimation(.easeOut(duration: 0.25)) { camera = .region(region) }
        } else {
            // Under the photo's fade, so the change from the guess screen's map isn't a cut.
            withAnimation(.easeOut(duration: 0.25)) {
                camera = GuessMySpotCamera.around(guess, meters: isSender ? 60_000 : 300_000)
            }
        }
    }

    private func moveCamera(to stage: GuessMySpotRevealTimeline.Camera) {
        guard let round, let guess = round.guess, let spot = round.spot else { return }
        let target: MapCameraPosition = switch stage {
        case .guess: GuessMySpotCamera.around(guess, meters: 60_000)
        case .overview: GuessMySpotCamera.framing(guess, spot)
        // A far guess has no landing: the view of both spots tells the story.
        case .landed: GuessMySpotCamera.landing(on: spot, guess: guess) ?? GuessMySpotCamera.framing(guess, spot)
        }
        let duration = stage == .landed ? timeline.schedule.landDuration : timeline.schedule.zoomOutDuration
        if reduceMotion || timeline.isSettled {
            camera = target
        } else {
            withAnimation(.easeInOut(duration: duration)) { camera = target }
        }
    }

    /// Where the real pin stands on screen once the camera landed: the middle of the
    /// map above the card.
    private var bloomOrigin: UnitPoint {
        let total = mapSize.height + Self.topRoom
        guard total > Self.topRoom else { return UnitPoint(x: 0.5, y: 0.3) }
        return UnitPoint(x: 0.5, y: (Self.topRoom + max(0, mapSize.height - cardHeight) / 2) / total)
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
            accessibilityValue: .guessMySpotMapPinDropped
        )
        .safeAreaPadding(.top, Self.topRoom)
        // The card's room is kept from the start, so every camera move frames the part
        // of the map the card leaves, and nothing slides when it rises.
        .safeAreaPadding(.bottom, cardHeight + PaeoniaSpacing.space8)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { mapSize = CGSize(width: $0.width, height: max(0, $0.height - Self.topRoom)) }
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

    // MARK: Photo and distance

    /// The photo on the top half, as the guess screen had it, until it slides away.
    private var photo: some View {
        GeometryReader { proxy in
            GuessMySpotPhotoPane(image: viewModel.roundPhoto)
                .frame(height: max(0, proxy.size.height / 2 - PaeoniaSpacing.space12))
                .background(.paeoniaSurfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16, style: .continuous))
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space8)
                .offset(y: timeline.photoAway && !reduceMotion ? -proxy.size.height / 2 - 40 : 0)
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
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
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
                    .accessibilityHidden(!timeline.cardShown)
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.bottom, PaeoniaSpacing.space8)
        .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
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

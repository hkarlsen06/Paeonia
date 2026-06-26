import MapKit
import SwiftUI
import UIKit

/// The map tile on the Us tab: a dark-mode map that fills the whole card, framed
/// to show both partners with their avatars, and the live distance overlaid at the
/// bottom. The map is rendered with `MKMapSnapshotter` so it has no Apple Maps
/// attribution overlay and so the camera framing and pin placement are fully under
/// our control.
///
/// Coordinates are placeholder values for now. Once partner location sharing is
/// wired up, feed real coordinates in and the snapshot reframes and recomputes the
/// distance automatically.
struct CoupleMapCard: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?

    // Placeholder coordinates until partner location sharing feeds real ones.
    // current = Hilde in Stout, Iowa; partner = Hjalmar in Alta, Norway.
    private static let currentCoordinate = CLLocationCoordinate2D(latitude: 42.5236, longitude: -92.7160)
    private static let partnerCoordinate = CLLocationCoordinate2D(latitude: 69.9689, longitude: 23.2716)

    // Placeholder capture times until real location updates carry their own.
    private static let currentCapturedAt = Date.now.addingTimeInterval(-8 * 60)
    private static let partnerCapturedAt = Date.now.addingTimeInterval(-3 * 60 * 60)

    var body: some View {
        // Tap blows a heart between the avatars; a long press opens Maps.
        CoupleMapSnapshot(
            currentName: currentName,
            currentProfilePhotoAssetID: currentProfilePhotoAssetID,
            currentCoordinate: Self.currentCoordinate,
            currentCapturedAt: Self.currentCapturedAt,
            partnerName: partnerName,
            partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
            partnerCoordinate: Self.partnerCoordinate,
            partnerCapturedAt: Self.partnerCapturedAt,
            onLongPress: openInAppleMaps
        )
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
        }
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.homeMapAccessibilityLabel))
        .accessibilityHint(Text(.homeMapOpenHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openInAppleMaps() }
    }

    /// Surfaces Apple Maps (and its attribution/legal) by opening both partners'
    /// locations in the Maps app.
    private func openInAppleMaps() {
        let you = MKMapItem(
            location: CLLocation(latitude: Self.currentCoordinate.latitude, longitude: Self.currentCoordinate.longitude),
            address: nil
        )
        you.name = currentName
        let partner = MKMapItem(
            location: CLLocation(latitude: Self.partnerCoordinate.latitude, longitude: Self.partnerCoordinate.longitude),
            address: nil
        )
        partner.name = partnerName
        MKMapItem.openMaps(
            with: [you, partner],
            launchOptions: [MKLaunchOptionsMapTypeKey: NSNumber(value: MKMapType.standard.rawValue)]
        )
    }
}

/// Renders the dark map snapshot, overlays each partner's avatar at its mapped
/// point, and floats the distance over a scrim at the bottom.
private struct CoupleMapSnapshot: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let currentCoordinate: CLLocationCoordinate2D
    let currentCapturedAt: Date
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    let partnerCoordinate: CLLocationCoordinate2D
    let partnerCapturedAt: Date
    let onLongPress: () -> Void

    /// How much bigger than the pins' own bounding box the framed area is, so the
    /// avatars (and their timestamps) sit well inside the card edges.
    private static let paddingFactor = 2.4
    /// How far south to nudge the camera (as a share of the framed span) so both
    /// pins ride above the bottom distance scrim.
    private static let southwardShiftFraction = 0.09
    private static let scrimHeight: CGFloat = 52
    /// Hard cap on simultaneous tap-spawned hearts, so rapid tapping can make a
    /// little chaos without growing unbounded work or memory.
    private static let maxConcurrentTapKisses = 16

    @State private var snapshot: SnapshotResult?
    @State private var tapKisses: [TapKiss] = []

    private struct SnapshotResult {
        let image: UIImage
        let currentPoint: CGPoint
        let partnerPoint: CGPoint
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background

                if let snapshot {
                    KissLayer(
                        start: snapshot.currentPoint,
                        end: snapshot.partnerPoint,
                        tapKisses: tapKisses
                    )

                    MapAvatarPin(
                        name: currentName,
                        assetID: currentProfilePhotoAssetID,
                        tint: .paeoniaPartnerOne,
                        capturedAt: currentCapturedAt,
                        point: snapshot.currentPoint,
                        containerWidth: proxy.size.width
                    )
                    .position(snapshot.currentPoint)

                    MapAvatarPin(
                        name: partnerName,
                        assetID: partnerProfilePhotoAssetID,
                        tint: .paeoniaPartnerTwo,
                        capturedAt: partnerCapturedAt,
                        point: snapshot.partnerPoint,
                        containerWidth: proxy.size.width
                    )
                    .position(snapshot.partnerPoint)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    distanceLabel
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .background(scrim)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onTapGesture { spawnTapKiss() }
            .onLongPressGesture(minimumDuration: 0.4) { onLongPress() }
            .task(id: proxy.size) {
                await loadSnapshot(size: proxy.size)
            }
        }
    }

    /// Spawns a heart that flies between the avatars right now. Several can be in
    /// flight at once; a hard cap plus per-kiss auto-removal keep it bounded.
    private func spawnTapKiss() {
        guard snapshot != nil else {
            return
        }
        if tapKisses.count >= Self.maxConcurrentTapKisses {
            tapKisses.removeFirst()
        }

        let kiss = TapKiss(
            bornAt: .now,
            plan: KissPlan(forward: Bool.random(), next: { Double.random(in: 0..<1) })
        )
        tapKisses.append(kiss)

        // Drop it once its flight is over so the array returns to empty.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(kiss.plan.flightDuration + 0.2))
            tapKisses.removeAll { $0.id == kiss.id }
        }
    }

    @ViewBuilder
    private var background: some View {
        if let snapshot {
            // MapKit has no grayscale or tintable map style, so desaturate the
            // snapshot and multiply the brand color over it for a plum duotone map.
            Image(uiImage: snapshot.image)
                .resizable()
                .scaledToFill()
                .grayscale(1)
                .colorMultiply(.paeoniaAccentPrimary)
        } else {
            Color.paeoniaBackgroundSecondary
        }
    }

    // The distance number and unit, right-aligned so it sits on the same line as
    // the Apple Maps watermark baked into the bottom-left of the snapshot.
    private var distanceLabel: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: "location.fill")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)

            Text(verbatim: distanceText)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.paeoniaAccentPrimary)
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        .padding(.trailing, PaeoniaSpacing.space12)
        .padding(.bottom, PaeoniaSpacing.tileCaptionBottomInset)
    }

    private var scrim: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.65)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: Self.scrimHeight)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var distanceText: String {
        let from = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let to = CLLocation(latitude: partnerCoordinate.latitude, longitude: partnerCoordinate.longitude)
        return Measurement(value: from.distance(from: to), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    @MainActor
    private func loadSnapshot(size: CGSize) async {
        guard size.width > 0, size.height > 0 else {
            return
        }

        // Muted standard config plays down roads, borders, and labels so the map
        // reads as a calm backdrop rather than a navigation map.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll

        let options = MKMapSnapshotter.Options()
        options.region = fittingRegion()
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = configuration

        let snapshotter = MKMapSnapshotter(options: options)
        guard let result = try? await snapshotter.start() else {
            return
        }

        snapshot = SnapshotResult(
            image: result.image,
            currentPoint: result.point(for: currentCoordinate),
            partnerPoint: result.point(for: partnerCoordinate)
        )
    }

    /// A square map rect that contains both pins with generous padding so the
    /// avatars stay clear of the edges, nudged south so they ride above the bottom
    /// distance scrim. Working in projected map points (rather than lat/lon degrees)
    /// keeps the framing square, so MapKit doesn't add its own aspect padding.
    private func fittingRegion() -> MKCoordinateRegion {
        let currentPoint = MKMapPoint(currentCoordinate)
        let partnerPoint = MKMapPoint(partnerCoordinate)

        let centerX = (currentPoint.x + partnerPoint.x) / 2
        let centerY = (currentPoint.y + partnerPoint.y) / 2

        // Floor the span so very-close coordinates still get a sensible zoom
        // instead of diving to street level.
        let midLatitude = (currentCoordinate.latitude + partnerCoordinate.latitude) / 2
        let minimumSpan = 2_000 * MKMapPointsPerMeterAtLatitude(midLatitude)
        let pinsSpan = max(abs(currentPoint.x - partnerPoint.x), abs(currentPoint.y - partnerPoint.y))
        let side = max(pinsSpan, minimumSpan) * Self.paddingFactor

        // Move the framed center south of the pins (larger y), so both avatars ride
        // up toward the top and clear the bottom distance scrim.
        let shiftedCenterY = centerY + side * Self.southwardShiftFraction

        let rect = MKMapRect(
            x: centerX - side / 2,
            y: shiftedCenterY - side / 2,
            width: side,
            height: side
        )
        return MKCoordinateRegion(rect)
    }
}

/// A partner's avatar pin: the same tinted, ringed avatar shown in the Home
/// toolbar, with a short relative timestamp of when the location was captured
/// floating just below it. The timestamp is an overlay so it doesn't shift the
/// avatar off its exact map point, and it slides sideways when needed so the badge
/// never spills outside the card.
private struct MapAvatarPin: View {
    let name: String
    let assetID: UUID?
    let tint: Color
    let capturedAt: Date
    let point: CGPoint
    let containerWidth: CGFloat

    @State private var badgeWidth: CGFloat = 0

    private static let edgeInset: CGFloat = 8

    private var diameter: CGFloat {
        PairingCelebrationProfilesView.Metrics.compact.avatarDiameter
    }

    /// Slides the badge horizontally so it stays inset from both card edges, while
    /// staying centered under the avatar whenever there is room.
    private var badgeOffsetX: CGFloat {
        guard badgeWidth > 0, containerWidth > 0 else {
            return 0
        }
        let halfWidth = badgeWidth / 2
        let minCenter = Self.edgeInset + halfWidth
        let maxCenter = containerWidth - Self.edgeInset - halfWidth
        guard minCenter <= maxCenter else {
            return 0
        }
        return min(max(point.x, minCenter), maxCenter) - point.x
    }

    var body: some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: assetID,
            name: name,
            tint: tint,
            size: diameter
        )
        .overlay(alignment: .top) {
            Text(capturedAt.formatted(Date.RelativeFormatStyle(presentation: .named, unitsStyle: .abbreviated)))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, PaeoniaSpacing.space8)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.5)))
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { badgeWidth = $0 }
                .offset(x: badgeOffsetX, y: diameter + PaeoniaSpacing.space4)
        }
    }
}

/// Shape of one heart's flight. Every value is drawn independently from the given
/// random source, so no two kisses share a path, speed, size, or wobble. The same
/// plan type drives both the ambient kisses (fed a deterministic per-slot sequence)
/// and the tap-spawned ones (fed the system RNG).
private struct KissPlan {
    let forward: Bool
    let flightDuration: Double
    let arcSign: CGFloat
    let arcMagnitude: CGFloat
    let loopTurns: CGFloat
    let loopSign: CGFloat
    let loopPhase: CGFloat
    let loopRadiusFactor: CGFloat
    let baseScale: CGFloat
    let rotationAmplitude: Double

    init(forward: Bool, next: () -> Double) {
        self.forward = forward
        // Slow, wind-like drift; speed varies kiss to kiss.
        flightDuration = 3.6 + next() * 3.0
        arcSign = next() < 0.5 ? -1 : 1
        arcMagnitude = 0.05 + CGFloat(next()) * 0.13
        loopPhase = CGFloat(next() * 2 * .pi)
        loopSign = next() < 0.5 ? -1 : 1

        // Only some kisses loop; the ones that do use 2–3 tighter turns of varying
        // size so the loops stay small while still crossing themselves.
        let hasLoop = next() < 0.6
        loopTurns = hasLoop ? (next() < 0.5 ? 2 : 3) : 0
        loopRadiusFactor = hasLoop ? (0.09 + CGFloat(next()) * 0.06) : 0

        baseScale = 0.8 + CGFloat(next()) * 0.5
        rotationAmplitude = 6 + next() * 10
    }
}

/// One tap-spawned heart in flight.
private struct TapKiss: Identifiable {
    let id = UUID()
    let bornAt: Date
    let plan: KissPlan
}

/// Pure math for a heart's flight: a lightly arced path with optional enveloped
/// loops, plus fade and scale, computed for a 0...1 progress value.
private enum KissMath {
    struct State {
        var position: CGPoint
        var opacity: Double
        var scale: CGFloat
        var rotation: Double
    }

    static func state(plan: KissPlan, start: CGPoint, end: CGPoint, progress: CGFloat) -> State {
        let from = plan.forward ? start : end
        let to = plan.forward ? end : start
        // Smootherstep eases the travel so it leaves one avatar and settles into the
        // other instead of moving at a constant clip.
        let along = smootherstep(progress)
        let (position, theta) = point(plan: plan, from: from, to: to, along: along)
        return State(
            position: position,
            opacity: fadeOpacity(progress),
            scale: scale(progress) * plan.baseScale,
            rotation: Double(sin(theta)) * plan.rotationAmplitude
        )
    }

    /// The loop radius grows enough mid-flight that the heart briefly backtracks —
    /// making real loops — and the envelope fades it to zero at both avatars for a
    /// clean launch and landing.
    private static func point(plan: KissPlan, from: CGPoint, to: CGPoint, along: CGFloat) -> (CGPoint, CGFloat) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = max(hypot(dx, dy), 1)

        let perpX = -dy / distance
        let perpY = dx / distance

        let envelope = sin(.pi * along)
        let arc = plan.arcSign * distance * plan.arcMagnitude * envelope
        let loopRadius = distance * plan.loopRadiusFactor * envelope
        let theta = plan.loopSign * 2 * .pi * plan.loopTurns * along + plan.loopPhase

        let computed = CGPoint(
            x: from.x + dx * along + perpX * arc + cos(theta) * loopRadius,
            y: from.y + dy * along + perpY * arc + sin(theta) * loopRadius
        )
        return (computed, theta)
    }

    private static func fadeOpacity(_ t: CGFloat) -> Double {
        let fadeIn = min(t / 0.18, 1)
        let fadeOut = min((1 - t) / 0.18, 1)
        return Double(max(min(fadeIn, fadeOut), 0))
    }

    private static func scale(_ t: CGFloat) -> CGFloat {
        if t < 0.15 {
            return 0.6 + (t / 0.15) * 0.4
        }
        if t > 0.85 {
            return 1 + ((t - 0.85) / 0.15) * 0.2
        }
        return 1
    }

    private static func smootherstep(_ t: CGFloat) -> CGFloat {
        let c = min(max(t, 0), 1)
        return c * c * c * (c * (c * 6 - 15) + 10)
    }

    /// A stateless splitmix64-style hash mapped to 0..<1, so randomness is
    /// reproducible from a seed alone.
    static func random01(_ seed: Int) -> Double {
        var x = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x = x ^ (x >> 31)
        return Double(x >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A deterministic sequence of pseudo-random values from one seed, for the
    /// ambient kiss (recomputed every frame, so it must be reproducible per slot).
    static func hashedSequence(seed: Int) -> () -> Double {
        var index = 0
        return {
            let value = random01(seed &+ index)
            index += 1
            return value
        }
    }
}

/// Draws every blown heart — the low-frequency ambient kiss plus any tap-spawned
/// ones — in a single timeline so there is just one display-link driver. Hidden
/// under Reduce Motion.
private struct KissLayer: View {
    let start: CGPoint
    let end: CGPoint
    let tapKisses: [TapKiss]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Length of each ambient scheduling slot. The kiss happens at a random moment
    /// inside its slot, so the gap between kisses keeps shifting.
    private static let slotPeriod: TimeInterval = 16

    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { context in
                let now = context.date
                ZStack {
                    if let state = ambientState(at: now) {
                        heart(state)
                    }
                    ForEach(tapKisses) { kiss in
                        if let state = tapState(kiss, at: now) {
                            heart(state)
                        }
                    }
                }
            }
        }
    }

    private func heart(_ state: KissMath.State) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.paeoniaAccentSecondary)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .rotationEffect(.degrees(state.rotation))
            .scaleEffect(state.scale)
            .opacity(state.opacity)
            .position(state.position)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func ambientState(at date: Date) -> KissMath.State? {
        let time = date.timeIntervalSinceReferenceDate
        let slot = Int(floor(time / Self.slotPeriod))
        let plan = KissPlan(
            forward: slot.isMultiple(of: 2),
            next: KissMath.hashedSequence(seed: slot &* 31)
        )
        let startOffset = KissMath.random01(slot &* 31 &- 1) * (Self.slotPeriod - plan.flightDuration)
        let phase = time - Double(slot) * Self.slotPeriod

        guard phase >= startOffset, phase < startOffset + plan.flightDuration else {
            return nil
        }
        let progress = CGFloat((phase - startOffset) / plan.flightDuration)
        return KissMath.state(plan: plan, start: start, end: end, progress: progress)
    }

    private func tapState(_ kiss: TapKiss, at date: Date) -> KissMath.State? {
        let elapsed = date.timeIntervalSince(kiss.bornAt)
        guard elapsed >= 0, elapsed <= kiss.plan.flightDuration else {
            return nil
        }
        let progress = CGFloat(elapsed / kiss.plan.flightDuration)
        return KissMath.state(plan: kiss.plan, start: start, end: end, progress: progress)
    }
}

#if DEBUG
#Preview {
    HStack(spacing: PaeoniaSpacing.space16) {
        CoupleMapCard(
            currentName: "Hjalmar",
            currentProfilePhotoAssetID: nil,
            partnerName: "Oda",
            partnerProfilePhotoAssetID: nil
        )
        Color.clear
    }
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif

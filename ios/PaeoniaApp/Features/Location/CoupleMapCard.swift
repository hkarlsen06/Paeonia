import MapKit
import SwiftUI
import UIKit

/// The map tile on the Us tab: a dark-mode map that fills the whole card, framed
/// to show both partners with their avatars, and the live distance overlaid at the
/// bottom. The map is rendered with `MKMapSnapshotter` so it has no Apple Maps
/// attribution overlay and so the camera framing and pin placement are fully under
/// our control.
struct CoupleMapCard: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    let state: CoupleMapState
    var onPromptCurrentLocation: () -> Void = {}

    @ViewBuilder
    var body: some View {
        switch state {
        case let .ready(current, partner):
            // Tap blows heart between avatars; long press opens Maps.
            mapTile {
                CoupleMapSnapshot(
                    currentName: currentName,
                    currentProfilePhotoAssetID: currentProfilePhotoAssetID,
                    currentCoordinate: current.coordinate,
                    currentCapturedAt: current.capturedAt,
                    partnerName: partnerName,
                    partnerProfilePhotoAssetID: partnerProfilePhotoAssetID,
                    partnerCoordinate: partner.coordinate,
                    partnerCapturedAt: partner.capturedAt,
                    onLongPress: {
                        openInAppleMaps(current: current, partner: partner)
                    }
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.homeMapAccessibilityLabel(partnerName)))
            .accessibilityHint(Text(.homeMapOpenHint))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                openInAppleMaps(current: current, partner: partner)
            }
        case .loading:
            mapTile {
                Color.paeoniaBackgroundSecondary
            }
            .accessibilityHidden(true)
        case .currentUnknown:
            mapTile {
                MapEmptyState(
                    title: .homeMapCurrentUnknownTitle,
                    message: .homeMapCurrentUnknownMessage,
                    systemImage: "location.slash.fill",
                    actionTitle: .homeMapCurrentUnknownButton,
                    actionSystemImage: "location.fill",
                    action: onPromptCurrentLocation
                )
            }
        case let .partnerUnknown(reason):
            mapTile {
                MapEmptyState(
                    title: partnerUnknownTitle(for: reason),
                    message: .homeMapPartnerUnknownMessage(partnerName),
                    systemImage: "location.slash.fill"
                )
            }
        }
    }

    private func openInAppleMaps(current: LocationPoint, partner: LocationPoint) {
        let you = MKMapItem(
            location: CLLocation(latitude: current.latitude, longitude: current.longitude),
            address: nil
        )
        you.name = currentName
        let partner = MKMapItem(
            location: CLLocation(latitude: partner.latitude, longitude: partner.longitude),
            address: nil
        )
        partner.name = partnerName
        MKMapItem.openMaps(
            with: [you, partner],
            launchOptions: [MKLaunchOptionsMapTypeKey: NSNumber(value: MKMapType.standard.rawValue)]
        )
    }

    private func mapTile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .aspectRatio(2, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                    .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
            }
            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }

    private func partnerUnknownTitle(for reason: PartnerLocationVisibilityState) -> LocalizedStringResource {
        switch reason {
        case .relationshipEnded:
            .homeMapRelationshipEndedTitle
        case .disabled, .notSharing, .visible, .unknown:
            .homeMapPartnerUnknownTitle(partnerName)
        }
    }
}

private extension LocationPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct MapEmptyState: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let systemImage: String
    var actionTitle: LocalizedStringResource?
    var actionSystemImage: String?
    var action: (() -> Void)?

    var body: some View {
        ZStack {
            Color.paeoniaBackgroundSecondary

            VStack(spacing: PaeoniaSpacing.space8) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .accessibilityHidden(true)

                VStack(spacing: PaeoniaSpacing.space4) {
                    Text(title)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(PaeoniaTypography.caption)
                        .foregroundStyle(.paeoniaTextSecondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                }

                if let actionTitle, let action {
                    Button(action: action) {
                        Label {
                            Text(actionTitle)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } icon: {
                            if let actionSystemImage {
                                Image(systemName: actionSystemImage)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaTextInverse)
                    .padding(.horizontal, PaeoniaSpacing.space12)
                    .padding(.vertical, PaeoniaSpacing.space8)
                    .background(.paeoniaAccentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
                    .buttonStyle(.plain)
                }
            }
            .padding(PaeoniaSpacing.space12)
        }
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

    /// How much larger than the pins' own span the framed area is, leaving an even
    /// margin around the avatars.
    private static let paddingFactor = 1.7
    /// Smallest framed span (meters) so same-city couples still get a sensible zoom
    /// instead of diving to street level.
    private static let minimumSpanMeters: CLLocationDegrees = 4_000
    private static let scrimHeight: CGFloat = 52
    /// Hard cap on simultaneous tap-spawned hearts, so rapid tapping can make a
    /// little chaos without growing unbounded work or memory.
    private static let maxConcurrentTapKisses = 16
    /// Lean of the sweep line away from vertical, so it cuts across on a diagonal.
    private static let tiltRadians: CGFloat = 18 * .pi / 180
    private static let sweepDuration: TimeInterval = 1.5
    /// The reveal uses the app's standard ease-in-ease-out curve (`PaeoniaMotion`) at the
    /// sweep duration, so the flame's motion matches the rest of the app.
    private static let sweepCurve = PaeoniaMotion.standardCurve(duration: sweepDuration)
    /// A partner must move at least this fraction of the framed span for the sweep to
    /// play — below it the two maps look identical, so the new one swaps in silently.
    /// The framed span is floored at `minimumSpanMeters`, the map's tightest framing.
    private static let minimumMoveFraction: Double = 0.06

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The current map + avatars, shown underneath — what the sweep reveals.
    @State private var snapshot: SnapshotResult?
    /// The previous map + avatars, laid over the new one and burned away by the sweep.
    /// Nil on the first load, where the cover falls back to the empty backdrop.
    @State private var outgoing: SnapshotResult?
    /// Whether a sweep is in progress (so the burning cover and flame are mounted).
    @State private var isRevealing = false
    /// 0 → 1 as the flame front crosses the tile, burning the cover (old map + old
    /// avatars) away to reveal the new map + new avatars beneath.
    @State private var sweep: CGFloat = 1
    /// Bumped each time a sweep starts; the deferred start and completion only act while
    /// it still matches, so a superseding sweep wins and silent swaps don't disturb one.
    @State private var revealToken = 0
    /// The positions the on-screen map was last *swept* for. The next sweep is measured
    /// from here (not the last silent swap), so a series of tiny drifts accumulates toward
    /// the threshold instead of resetting each time.
    @State private var sweptCurrent: CLLocationCoordinate2D?
    @State private var sweptPartner: CLLocationCoordinate2D?
    /// The request the current `snapshot` was rendered for. `.task` restarts each
    /// time this tile reappears (e.g. switching back to the Us tab), so we keep this
    /// to recognize an identical re-entry and skip the work instead of re-rendering.
    @State private var lastRenderedRequest: SnapshotRequest?
    @State private var tapKisses: [TapKiss] = []

    /// One rendered map plus the two avatar points on it. The whole thing is revealed as a
    /// unit — map and avatars together — so the flame hides the old positions while
    /// uncovering the new ones.
    private struct SnapshotResult {
        let image: UIImage
        let currentPoint: CGPoint
        let partnerPoint: CGPoint
    }

    private struct SnapshotRequest: Hashable {
        let width: CGFloat
        let height: CGFloat
        let currentLatitude: CLLocationDegrees
        let currentLongitude: CLLocationDegrees
        let partnerLatitude: CLLocationDegrees
        let partnerLongitude: CLLocationDegrees

        init(
            size: CGSize,
            currentCoordinate: CLLocationCoordinate2D,
            partnerCoordinate: CLLocationCoordinate2D
        ) {
            width = size.width
            height = size.height
            currentLatitude = currentCoordinate.latitude
            currentLongitude = currentCoordinate.longitude
            partnerLatitude = partnerCoordinate.latitude
            partnerLongitude = partnerCoordinate.longitude
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.paeoniaBackgroundSecondary

                // The current map and avatars, shown underneath — what the sweep reveals.
                if let snapshot {
                    mapContent(snapshot, size: size)
                }

                // The burning cover: the old map + old avatars (or the backdrop on first
                // load), masked to the part the flame hasn't reached and burned away to
                // reveal the new map + new avatars beneath. Avatars ride along inside the
                // cover, so the old ones are hidden and the new ones uncovered by the line.
                if isRevealing {
                    revealCover(size: size)
                        .mask(alignment: .topLeading) {
                            UnsweptRegionShape(progress: sweep, tilt: Self.tiltRadians)
                        }

                    FlameSweepLine(progress: sweep, tilt: Self.tiltRadians)
                        .allowsHitTesting(false)
                }

                // Hearts fly between the avatars — so only once the avatars are actually
                // on screen. Suppressed during a sweep (the avatars are still being
                // uncovered) and whenever there's no map yet, so a heart never flies over
                // empty space.
                if let snapshot, !isRevealing {
                    KissLayer(
                        start: snapshot.currentPoint,
                        end: snapshot.partnerPoint,
                        tapKisses: tapKisses
                    )
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    distanceLabel
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .background(scrim)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { spawnTapKiss() }
            .onLongPressGesture(minimumDuration: 0.4) { onLongPress() }
            .task(id: snapshotRequest(size: size)) {
                await loadSnapshot(size: size)
            }
        }
    }

    /// The full revealed unit: the duotone map with both avatar pins placed on it. The
    /// reveal masks this as a whole, so a partner's avatar is hidden at its old position
    /// and uncovered at its new one as the flame passes.
    @ViewBuilder
    private func mapContent(_ snap: SnapshotResult, size: CGSize) -> some View {
        ZStack {
            duotone(snap.image, size)

            MapAvatarPin(
                name: currentName,
                assetID: currentProfilePhotoAssetID,
                tint: .paeoniaPartnerOne,
                capturedAt: currentCapturedAt,
                showsTimestamp: false,
                point: snap.currentPoint,
                containerWidth: size.width
            )
            .position(snap.currentPoint)

            MapAvatarPin(
                name: partnerName,
                assetID: partnerProfilePhotoAssetID,
                tint: .paeoniaPartnerTwo,
                capturedAt: partnerCapturedAt,
                showsTimestamp: true,
                // Hang the badge toward the other pin (the map interior) so it never
                // reaches the card edge: below when the partner is the upper pin, above
                // when it's the lower one.
                badgeBelow: snap.partnerPoint.y <= snap.currentPoint.y,
                point: snap.partnerPoint,
                containerWidth: size.width
            )
            .position(snap.partnerPoint)
        }
    }

    /// The layer the flame burns away: the outgoing map + avatars when there is one,
    /// otherwise the plain backdrop so the very first map still sweeps in.
    @ViewBuilder
    private func revealCover(size: CGSize) -> some View {
        if let outgoing {
            mapContent(outgoing, size: size)
        } else {
            Color.paeoniaBackgroundSecondary
        }
    }

    /// The brand duotone: MapKit has no grayscale/tintable style, so desaturate the
    /// snapshot and multiply the plum accent over it.
    private func duotone(_ uiImage: UIImage, _ size: CGSize) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .grayscale(1)
            .colorMultiply(.paeoniaAccentPrimary)
    }

    /// Spawns a heart that flies between the avatars right now. Several can be in
    /// flight at once; a hard cap plus per-kiss auto-removal keep it bounded.
    private func spawnTapKiss() {
        // No heart without visible avatars to fly between: ignore taps before the first
        // map and while a sweep is still uncovering them.
        guard snapshot != nil, !isRevealing else {
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

    private func snapshotRequest(size: CGSize) -> SnapshotRequest {
        SnapshotRequest(
            size: size,
            currentCoordinate: currentCoordinate,
            partnerCoordinate: partnerCoordinate
        )
    }

    @MainActor
    private func loadSnapshot(size: CGSize) async {
        guard size.width > 0, size.height > 0 else {
            return
        }

        // The .task restarts whenever this tile reappears, not only when its inputs
        // change, so re-entering the Us tab would otherwise re-render an identical
        // map. Skip the work when we already hold the image for this exact request.
        let request = snapshotRequest(size: size)
        if snapshot != nil, lastRenderedRequest == request {
            return
        }

        // Muted standard config plays down roads, borders, and labels so the map
        // reads as a calm backdrop rather than a navigation map.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll

        let options = MKMapSnapshotter.Options()
        options.region = fittingRegion(aspectRatio: size.width / size.height)
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = configuration

        let snapshotter = MKMapSnapshotter(options: options)
        guard let result = try? await snapshotter.start() else {
            return
        }

        // Adopt the finished map+avatars. `adopt` keeps the last one visible and sweeps
        // the new one in (or swaps silently for a small move), so a refresh never flashes.
        let new = SnapshotResult(
            image: result.image,
            currentPoint: result.point(for: currentCoordinate),
            partnerPoint: result.point(for: partnerCoordinate)
        )
        lastRenderedRequest = request
        adopt(new)
    }

    /// A map rect that contains both pins, built to the card's aspect ratio so MapKit
    /// renders it as-is. (A square rect was being re-expanded by MapKit to fill the
    /// wide card, which undid the framing and made tuning feel like it did nothing.)
    /// Working in projected map points keeps the math uniform; intersecting `.world`
    /// keeps the region inside valid Mercator bounds.
    private func fittingRegion(aspectRatio: Double) -> MKCoordinateRegion {
        let current = MKMapPoint(currentCoordinate)
        let partner = MKMapPoint(partnerCoordinate)

        let midLatitude = (currentCoordinate.latitude + partnerCoordinate.latitude) / 2
        let minimumHalf = Self.minimumSpanMeters / 2 * MKMapPointsPerMeterAtLatitude(midLatitude)

        var halfWidth = max(abs(current.x - partner.x) / 2, minimumHalf) * Self.paddingFactor
        var halfHeight = max(abs(current.y - partner.y) / 2, minimumHalf) * Self.paddingFactor

        // Grow the short side to the card's shape so the framed rect matches the
        // image; otherwise MapKit expands it and re-centers the pins.
        if halfWidth / halfHeight < aspectRatio {
            halfWidth = halfHeight * aspectRatio
        } else {
            halfHeight = halfWidth / aspectRatio
        }

        // Center on both pins so each avatar sits the same distance from its edge.
        // The timestamp badge keeps clear of the edges by flipping to the map-facing
        // side of its avatar (see MapAvatarPin), so the framing needs no bias.
        let rect = MKMapRect(
            x: (current.x + partner.x) / 2 - halfWidth,
            y: (current.y + partner.y) / 2 - halfHeight,
            width: halfWidth * 2,
            height: halfHeight * 2
        )
        return MKCoordinateRegion(rect.intersection(.world))
    }

    // MARK: Reveal

    /// Adopts a freshly rendered map + avatars. The new one always becomes the base
    /// (shown underneath); when a partner has moved far enough — or on the first map — the
    /// previous one is laid over it and burned away by the flame sweep. A same-place
    /// re-render swaps silently and never disturbs a sweep already in flight.
    private func adopt(_ new: SnapshotResult) {
        let previous = snapshot
        let isFirstMap = previous == nil
        let movedEnough = hasMovedEnough()

        // The new map + avatars become the base immediately and stay put; the cover is
        // laid over them and burned away. Promoting the base up front (not at the end) is
        // what keeps the finish seamless.
        snapshot = new

        // Reduce Motion never sweeps: show the new map outright, dropping any cover.
        if reduceMotion {
            endReveal()
            return
        }

        // A same-place update (small drift, rotation, or a sync re-read) just swaps the
        // map underneath. Crucially, do NOT tear down a sweep that's already in flight —
        // that would snap it straight to its end. If nothing is sweeping the state is
        // already clean. The sweep baseline is left alone so small drifts accumulate.
        guard isFirstMap || movedEnough else {
            return
        }

        // This sweep's positions become the baseline the next move is measured against.
        sweptCurrent = currentCoordinate
        sweptPartner = partnerCoordinate

        // Tag this sweep so its deferred start and completion only act if no newer sweep
        // has begun — a silent swap mid-sweep must not make this one's completion bail
        // (which would strand the cover and flame at the edge).
        revealToken += 1
        let token = revealToken

        // Mount the burning cover (old content, or the backdrop on first load) at the
        // hidden start, then animate on the next tick — a same-tick reset-then-animate
        // would interpolate from the previous value and skip the sweep entirely.
        outgoing = previous
        isRevealing = true
        sweep = 0
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard revealToken == token else { return }
            withAnimation(Self.sweepCurve) {
                sweep = 1
            } completion: {
                guard revealToken == token else { return }
                endReveal()
            }
        }
    }

    /// Whether either partner has moved far enough from the last-swept positions to look
    /// different on the map. The threshold scales with how far apart the partners are (the
    /// map's framing), so a small wobble that's invisible on a regional map never triggers
    /// a sweep. No baseline yet means "not a move" — the first map is handled separately.
    private func hasMovedEnough() -> Bool {
        guard let sweptCurrent, let sweptPartner else {
            return false
        }
        let currentMove = distanceMeters(currentCoordinate, sweptCurrent)
        let partnerMove = distanceMeters(partnerCoordinate, sweptPartner)
        let span = max(distanceMeters(currentCoordinate, partnerCoordinate), Self.minimumSpanMeters)
        return max(currentMove, partnerMove) > span * Self.minimumMoveFraction
    }

    private func distanceMeters(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    /// Tears down the burning cover without animation, leaving the already-revealed new
    /// map clean with no residual mask or flame.
    private func endReveal() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isRevealing = false
            outgoing = nil
            sweep = 1
        }
    }
}

/// The region the flame front has NOT yet reached: everything from the advancing,
/// angled front to the trailing edge. Masks the burning cover, so at `progress` 1 this
/// region is empty and the cover is fully gone. Animatable so the mask recedes in step
/// with the flame line.
private struct UnsweptRegionShape: Shape {
    var progress: CGFloat
    let tilt: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let (topX, bottomX) = SweepFront.edges(in: rect, progress: progress, tilt: tilt)
        // Over-extend to the right so the un-swept region always reaches the trailing
        // edge; the angled left boundary is the advancing front.
        let rightEdge = max(topX, bottomX) + rect.width

        var path = Path()
        path.move(to: CGPoint(x: topX, y: rect.minY))
        path.addLine(to: CGPoint(x: rightEdge, y: rect.minY))
        path.addLine(to: CGPoint(x: rightEdge, y: rect.maxY))
        path.addLine(to: CGPoint(x: bottomX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The glowing pink line at the sweep front: three layered strokes — a soft outer bloom,
/// a brighter inner glow, and a crisp core — all in the brand pink and full-strength the
/// whole length, so it reads as one uniformly thick, glowing streak.
private struct FlameSweepLine: View {
    var progress: CGFloat
    let tilt: CGFloat

    var body: some View {
        ZStack {
            FlameFrontShape(progress: progress, tilt: tilt)
                .stroke(outerGlow, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .blur(radius: 10)
                .blendMode(.screen)

            FlameFrontShape(progress: progress, tilt: tilt)
                .stroke(innerGlow, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .blur(radius: 2.5)
                .blendMode(.screen)

            FlameFrontShape(progress: progress, tilt: tilt)
                .stroke(core, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    // A glowing line in the brand pink: a deeper-pink halo (paeoniaAccentSecondary)
    // around the CTA pink (paeoniaAccentPrimary) core. Solid, full-strength colour the
    // whole length so the line reads as one uniformly thick pink streak — the layered
    // blur and screen blend give the glow, not a gradient.
    private var outerGlow: Color { .paeoniaAccentSecondary }
    private var innerGlow: Color { .paeoniaAccentPrimary }
    private var core: Color { .paeoniaAccentPrimary }
}

/// The bare line at the sweep front, drawn slightly past the top and bottom edges so
/// the flame's round caps stay out of frame. Animatable so it rides the sweep.
private struct FlameFrontShape: Shape {
    var progress: CGFloat
    let tilt: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let (topX, bottomX) = SweepFront.edges(in: rect, progress: progress, tilt: tilt)
        var path = Path()
        path.move(to: CGPoint(x: topX, y: rect.minY - 8))
        path.addLine(to: CGPoint(x: bottomX, y: rect.maxY + 8))
        return path
    }
}

/// Shared geometry for the sweep front so the mask and the flame line always agree on
/// where the advancing, tilted line sits for a given progress.
private enum SweepFront {
    /// How far the flame's glow spreads beyond the bright line (outer stroke half-width
    /// plus its blur). The front starts and ends this far *past* each edge so the glow
    /// halo never bleeds onto the card before the line has actually swept in (or after it
    /// has left) — it's only at the edge that the front carries a visible glow.
    static let glowMargin: CGFloat = 30

    /// The x of the front where it meets the top and bottom edges. At `progress` 0 the
    /// tilted line — and its full glow — sits just past the leading edge, so the cover
    /// fully covers the tile and nothing glows onto it; at `progress` 1 it sits just past
    /// the trailing edge, fully gone. Travel spans `width + slant` plus a `glowMargin` of
    /// off-tile run at each end so the glow clears the card cleanly without the line
    /// wandering far enough to leave a dead stretch mid-card.
    static func edges(in rect: CGRect, progress: CGFloat, tilt: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let slant = rect.height * tan(tilt)
        let startCenter = rect.minX - slant / 2 - glowMargin
        let travel = rect.width + slant + glowMargin * 2
        let center = startCenter + progress * travel
        return (top: center + slant / 2, bottom: center - slant / 2)
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
    let showsTimestamp: Bool
    /// Whether the timestamp badge hangs below the avatar (toward the bottom) or
    /// above it. Set so the badge always points into the map, never at a card edge.
    var badgeBelow: Bool = true
    let point: CGPoint
    let containerWidth: CGFloat

    @State private var badgeWidth: CGFloat = 0

    private static let edgeInset: CGFloat = 8
    private static let avatarDiameter: CGFloat = 36
    private static let badgeRefreshInterval: TimeInterval = 30

    private var diameter: CGFloat {
        Self.avatarDiameter
    }

    /// Offset that pushes the badge just past the avatar so a small gap shows
    /// between them, applied downward when below and upward when above.
    private var badgeDrop: CGFloat {
        diameter + PaeoniaSpacing.space4
    }

    /// Slides the badge horizontally so it stays inset from both card edges, while
    /// staying centered on the avatar whenever there is room.
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
        .overlay(alignment: badgeBelow ? .top : .bottom) {
            if showsTimestamp {
                LiveRelativeTimestampText(
                    capturedAt: capturedAt,
                    refreshInterval: Self.badgeRefreshInterval
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, PaeoniaSpacing.space8)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.5)))
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { badgeWidth = $0 }
                .offset(x: badgeOffsetX, y: badgeBelow ? badgeDrop : -badgeDrop)
            }
        }
    }
}

private struct LiveRelativeTimestampText: View {
    let capturedAt: Date
    let refreshInterval: TimeInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            Text(displayDate(asOf: context.date).formatted(Self.relativeStyle).capitalizedFirstLetter)
        }
    }

    private static let relativeStyle = Date.RelativeFormatStyle(
        presentation: .named,
        unitsStyle: .abbreviated
    )

    private func displayDate(asOf referenceDate: Date) -> Date {
        min(capturedAt, referenceDate)
    }
}

private extension String {
    /// Uppercases only the first character, leaving the rest untouched. Relative
    /// date styles like "for 3 t siden" come back lowercased, but as a standalone
    /// badge it should read like a label ("For 3 t siden").
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + String(dropFirst())
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
    CoupleMapCard(
        currentName: "Hjalmar",
        currentProfilePhotoAssetID: nil,
        partnerName: "Oda",
        partnerProfilePhotoAssetID: nil,
        state: .partnerUnknown(.notSharing)
    )
    .padding(PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif

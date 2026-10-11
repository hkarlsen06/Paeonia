import MapKit
import SwiftUI
import UIKit

/// The inputs a rendered map depends on. `.task` restarts each time the tile
/// reappears (e.g. switching back to the Us tab), so the snapshot view keeps the
/// request its map was rendered for and skips the work on an identical re-entry.
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

/// Renders the dark map snapshot, overlays each partner's avatar at its mapped
/// point, and floats the partner's location age over a scrim at the top and the
/// distance over one at the bottom.
struct CoupleMapSnapshot: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let currentCoordinate: CLLocationCoordinate2D
    let currentCapturedAt: Date
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    let partnerCoordinate: CLLocationCoordinate2D
    let partnerCapturedAt: Date
    let partnerWasStaleAtLastRefresh: Bool
    /// Both partners are in the same place right now (see `CoupleMapFraming.areTogether`).
    /// Shows a heart between the avatars and "Together" in place of the distance.
    let isTogether: Bool
    let onLongPress: () -> Void

    private static let scrimHeight: CGFloat = 52
    /// Closest the two avatar centers may sit on screen: one avatar plus room for the
    /// together heart between them.
    private static let minimumPinSpacing = MapAvatarPin.avatarDiameter + 20
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
    /// play. Below it the two maps look identical, so the new one swaps in silently.
    /// The framed span is floored at `CoupleMapFraming.minimumSpanMeters`, the map's
    /// tightest framing.
    private static let minimumMoveFraction: Double = 0.06
    /// Waits between failed map renders. A render is tried once more after each wait,
    /// so three attempts in total.
    private static let retryDelays: [Duration] = [.seconds(2), .seconds(5)]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.launchSidesUncovered) private var launchSidesUncovered

    /// The current map + avatars after the latest completed reveal.
    @State private var snapshot: SnapshotResult?
    /// The rendered map + avatars currently being swept in. This is intentionally
    /// separate from `snapshot` so a newly rendered first map cannot appear in full
    /// before the reveal mask has started.
    @State private var incoming: SnapshotResult?
    /// The previous map + avatars, laid over the incoming one and burned away by the sweep.
    /// Nil on the first load, where the cover falls back to the empty backdrop.
    @State private var outgoing: SnapshotResult?
    /// Whether a sweep is in progress (so the burning cover and flame are mounted).
    @State private var isRevealing = false
    /// 0 to 1 as the flame front crosses the tile, burning the cover (old map + old
    /// avatars) away to reveal the new map + new avatars beneath.
    @State private var sweep: CGFloat = 1
    /// Bumped each time a sweep starts; the deferred start and completion only act while
    /// it still matches, so a superseding sweep wins and silent swaps don't disturb one.
    @State private var revealToken = 0
    /// A sweep that's mounted but waiting for the cold-launch intro to finish before it
    /// runs (holds its `revealToken`), so the first map sweeps in where it can be seen.
    @State private var pendingLaunchReveal: Int?
    /// The positions the on-screen map was last *swept* for. The next sweep is measured
    /// from here (not the last silent swap), so a series of tiny drifts accumulates toward
    /// the threshold instead of resetting each time.
    @State private var sweptCurrent: CLLocationCoordinate2D?
    @State private var sweptPartner: CLLocationCoordinate2D?
    /// The request the current `snapshot` was rendered for. Never set for a fallback
    /// without a map, so the next run tries a real map again.
    @State private var lastRenderedRequest: SnapshotRequest?
    @State private var tapKisses: [TapKiss] = []

    /// One rendered map plus the two avatar points on it. The whole thing is revealed as a
    /// unit (map and avatars together) so the flame hides the old positions while
    /// uncovering the new ones. `image` is nil for the fallback shown when the map could
    /// not be rendered: just the backdrop with the avatars at fixed spots.
    private struct SnapshotResult {
        let image: UIImage?
        let currentPoint: CGPoint
        let partnerPoint: CGPoint
    }

    /// The map currently visible under the reveal cover. Keeping it in one stable
    /// view slot preserves the avatar image state when a sweep finishes.
    private var visibleSnapshot: SnapshotResult? {
        incoming ?? snapshot
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            tileContent(size: size)
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture { spawnTapKiss() }
                .onLongPressGesture(minimumDuration: 0.4) { onLongPress() }
                .task(id: snapshotRequest(size: size)) {
                    await loadSnapshot(size: size)
                }
                .onChange(of: launchSidesUncovered) { _, uncovered in
                    guard uncovered, let token = pendingLaunchReveal else { return }
                    pendingLaunchReveal = nil
                    startSweep(token: token)
                }
        }
    }

    @ViewBuilder
    private func tileContent(size: CGSize) -> some View {
        ZStack {
            Color.paeoniaBackgroundSecondary

            if let visibleSnapshot {
                mapContent(visibleSnapshot, size: size)
                    .mask(alignment: .topLeading) {
                        if isRevealing {
                            SweptRegionShape(progress: sweep, tilt: Self.tiltRadians)
                        } else {
                            Rectangle()
                        }
                    }
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

            // Hearts fly between the avatars, so only once the avatars are actually
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
        }
    }

    /// The full revealed unit: the duotone map with both avatar pins, the partner's
    /// location age, and the distance pill placed on it. The reveal masks this as a whole, so the avatars and the
    /// distance are all uncovered together as the flame passes. None of them pop in.
    @ViewBuilder
    private func mapContent(_ snap: SnapshotResult, size: CGSize) -> some View {
        ZStack {
            duotone(snap.image, size)

            MapAvatarPin(
                name: currentName,
                assetID: currentProfilePhotoAssetID,
                tint: .paeoniaPartnerOne,
                capturedAt: currentCapturedAt
            )
            .position(snap.currentPoint)

            MapAvatarPin(
                name: partnerName,
                assetID: partnerProfilePhotoAssetID,
                tint: .paeoniaPartnerTwo,
                capturedAt: partnerCapturedAt,
                wasStaleAtLastRefresh: partnerWasStaleAtLastRefresh,
                dimsWhenStale: true
            )
            .position(snap.partnerPoint)

            if isTogether {
                togetherHeart(between: snap)
            }

            // The distance pill (scrim + number + icon) lives inside the revealed unit
            // too, so the sweep uncovers it along with the map and avatars instead of it
            // sitting on top from the first frame.
            VStack(spacing: 0) {
                partnerAgeLabel
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(scrim(edge: .top))
                Spacer(minLength: 0)
                distanceLabel
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(scrim(edge: .bottom))
            }
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
    /// snapshot and multiply the plum accent over it. Without an image (the fallback)
    /// it is just the plain backdrop.
    @ViewBuilder
    private func duotone(_ uiImage: UIImage?, _ size: CGSize) -> some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .grayscale(1)
                .colorMultiply(.paeoniaAccentPrimary)
        } else {
            Color.paeoniaBackgroundSecondary
        }
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

    private func togetherHeart(between snap: SnapshotResult) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.paeoniaAccentSecondary)
            .symbolEffect(.breathe)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .position(
                x: (snap.currentPoint.x + snap.partnerPoint.x) / 2,
                y: (snap.currentPoint.y + snap.partnerPoint.y) / 2
            )
            .accessibilityHidden(true)
    }

    // The distance number and unit, right-aligned so it sits on the same line as
    // the Apple Maps watermark baked into the bottom-left of the snapshot.
    private var distanceLabel: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: isTogether ? "person.2.fill" : "location.fill")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)

            Text(isTogether ? String(localized: .homeMapTogether) : distanceText)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
        }
        .foregroundStyle(.paeoniaAccentPrimary)
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        .padding(.trailing, PaeoniaSpacing.space12)
        .padding(.bottom, PaeoniaSpacing.tileCaptionBottomInset)
    }

    /// How long ago the partner's location was recorded ("3 min"), styled like the
    /// distance. The card gives VoiceOver the full sentence instead.
    private var partnerAgeLabel: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 13, weight: .semibold))

                Text(verbatim: PartnerLocationRecordedStatus.shortAge(
                    capturedAt: partnerCapturedAt,
                    now: context.date
                ))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .lineLimit(1)
            }
        }
        .foregroundStyle(.paeoniaAccentPrimary)
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        .padding(.trailing, PaeoniaSpacing.space12)
        .padding(.top, PaeoniaSpacing.tileCaptionBottomInset)
        .accessibilityHidden(true)
    }

    /// A gradient darkening the map toward `edge`, so a label there stays readable.
    private func scrim(edge: VerticalEdge) -> some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.65)],
            startPoint: edge == .top ? .bottom : .top,
            endPoint: edge == .top ? .top : .bottom
        )
        .frame(height: Self.scrimHeight)
        .frame(maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
        .allowsHitTesting(false)
    }

    private var distanceText: String {
        Self.formattedDistance(from: currentCoordinate, to: partnerCoordinate)
    }

    /// The road distance between two points as shown on the map pill. The card also
    /// reads it out through VoiceOver, so both use this one formatter.
    static func formattedDistance(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> String {
        Measurement(value: distanceMeters(origin, destination), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private static func distanceMeters(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}

// MARK: Loading

extension CoupleMapSnapshot {
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
        if snapshot != nil || incoming != nil, lastRenderedRequest == request {
            return
        }

        let result = await renderMap(size: size)
        // A newer task (new coordinates or size) or a disappearing tile supersedes this
        // one. Stop here so an older result can never land after a newer one.
        guard !Task.isCancelled else {
            return
        }
        guard let rendered = result else {
            adoptFallbackIfNoMap(size: size)
            return
        }

        // Adopt the finished map+avatars. `adopt` keeps the last one visible and sweeps
        // the new one in (or swaps silently for a small move), so a refresh never flashes.
        lastRenderedRequest = request
        adopt(rendered)
    }

    /// Renders the map and both avatar points, trying again after each wait in
    /// `retryDelays` while the task is alive. Returns nil when every attempt failed or
    /// the task was cancelled.
    private func renderMap(size: CGSize) async -> SnapshotResult? {
        // Muted standard config plays down roads, borders, and labels so the map
        // reads as a calm backdrop rather than a navigation map.
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll

        let options = MKMapSnapshotter.Options()
        options.region = CoupleMapFraming.region(
            current: currentCoordinate,
            partner: partnerCoordinate,
            aspectRatio: size.width / size.height
        )
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.preferredConfiguration = configuration

        for attempt in 0...Self.retryDelays.count {
            if attempt > 0 {
                do {
                    try await Task.sleep(for: Self.retryDelays[attempt - 1])
                } catch {
                    return nil
                }
            }

            let snapshotter = MKMapSnapshotter(options: options)
            let result = try? await snapshotter.start()
            guard !Task.isCancelled else {
                return nil
            }
            if let result {
                // Partners closer than the map's tightest zoom can show would stack on one
                // spot, so spread the pins apart on screen until both faces show.
                let (currentPoint, partnerPoint) = CoupleMapFraming.separated(
                    result.point(for: currentCoordinate),
                    result.point(for: partnerCoordinate),
                    minimumDistance: Self.minimumPinSpacing
                )
                return SnapshotResult(
                    image: result.image,
                    currentPoint: currentPoint,
                    partnerPoint: partnerPoint
                )
            }
        }
        return nil
    }

    /// When every attempt failed and nothing is on screen yet, show the avatars and the
    /// distance on the plain backdrop instead of an empty tile. `lastRenderedRequest`
    /// stays untouched, so the next task run tries to render a real map again.
    private func adoptFallbackIfNoMap(size: CGSize) {
        guard snapshot == nil, incoming == nil else {
            return
        }
        adopt(SnapshotResult(
            image: nil,
            currentPoint: CGPoint(x: size.width * 0.3, y: size.height * 0.5),
            partnerPoint: CGPoint(x: size.width * 0.7, y: size.height * 0.5)
        ))
    }
}

// MARK: Reveal

extension CoupleMapSnapshot {
    /// Adopts a freshly rendered map + avatars. During a reveal the new map is held as
    /// `incoming` and shown only through the swept mask; it becomes the fully visible
    /// `snapshot` after the sweep completes. That keeps the first map from flashing in
    /// full before the blank cover is burned away.
    private func adopt(_ new: SnapshotResult) {
        let previous = incoming ?? snapshot
        // A fallback without a map image counts as "no map yet", so the first real map
        // still sweeps in over it.
        let isFirstMap = previous?.image == nil
        let movedEnough = hasMovedEnough()

        // Reduce Motion never sweeps: show the new map outright, dropping any cover.
        if reduceMotion {
            adoptSilently(new, updatesSweepBaseline: true)
            return
        }

        // A same-place update (small drift, rotation, or a sync re-read) just swaps the
        // map underneath. Crucially, do NOT tear down a sweep that's already in flight,
        // since that would snap it straight to its end. If nothing is sweeping the state is
        // already clean. The sweep baseline is left alone so small drifts accumulate.
        guard isFirstMap || movedEnough else {
            updateVisibleTargetSilently(new)
            return
        }

        // This sweep's positions become the baseline the next move is measured against.
        sweptCurrent = currentCoordinate
        sweptPartner = partnerCoordinate

        // Tag this sweep so its deferred start and completion only act if no newer sweep
        // has begun. A silent swap mid-sweep must not make this one's completion bail
        // (which would strand the cover and flame at the edge).
        revealToken += 1
        let token = revealToken

        // Mount the burning cover (old content, or the backdrop on first load) at the
        // hidden start while keeping the incoming map masked to the swept region. The
        // reset is deliberately non-animated; only the forward sweep animates.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            outgoing = previous
            incoming = new
            sweep = 0
            isRevealing = true
        }

        // Hold the sweep until the cold-launch intro's opening hole reaches the screen's
        // sides, so it plays where the user can see it rather than behind the overlay.
        // Then `onChange(launchSidesUncovered)` runs this token.
        guard launchSidesUncovered else {
            pendingLaunchReveal = token
            return
        }
        startSweep(token: token)
    }

    /// Runs the flame sweep for `token`, a beat after the cover mounts so the reset to
    /// `sweep = 0` commits first. A superseding reveal (newer token) cancels it.
    private func startSweep(token: Int) {
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
    /// a sweep. No baseline yet means "not a move"; the first map is handled separately.
    private func hasMovedEnough() -> Bool {
        guard let sweptCurrent, let sweptPartner else {
            return false
        }
        let currentMove = Self.distanceMeters(currentCoordinate, sweptCurrent)
        let partnerMove = Self.distanceMeters(partnerCoordinate, sweptPartner)
        let span = max(
            Self.distanceMeters(currentCoordinate, partnerCoordinate),
            CoupleMapFraming.minimumSpanMeters
        )
        return max(currentMove, partnerMove) > span * Self.minimumMoveFraction
    }

    private func adoptSilently(_ new: SnapshotResult, updatesSweepBaseline: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            snapshot = new
            incoming = nil
            outgoing = nil
            isRevealing = false
            sweep = 1
        }

        if updatesSweepBaseline {
            updateSweepBaseline()
        }
    }

    private func updateVisibleTargetSilently(_ new: SnapshotResult) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if isRevealing {
                incoming = new
            } else {
                snapshot = new
            }
        }
    }

    private func updateSweepBaseline() {
        sweptCurrent = currentCoordinate
        sweptPartner = partnerCoordinate
    }

    /// Tears down the burning cover without animation, leaving the already-revealed new
    /// map clean with no residual mask or flame.
    private func endReveal() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let incoming {
                snapshot = incoming
            }
            incoming = nil
            isRevealing = false
            outgoing = nil
            sweep = 1
        }
    }
}

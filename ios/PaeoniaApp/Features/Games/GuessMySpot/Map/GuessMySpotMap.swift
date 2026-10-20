import MapKit
import SwiftUI

/// The map every phase shares: Apple's standard map in the dark look, muted and
/// without points of interest, or the satellite map with labels. It pans and
/// zooms but never rotates or tilts, so north stays up. A tap reports where it
/// landed, and the screen decides what a tap does.
struct GuessMySpotMap: View {
    struct Pin: Identifiable {
        let id: String
        let coordinate: GuessMySpotCoordinate
        let style: BoardPieceStyle
        var opacity: Double = 1
        var glow: CGFloat = 0
        /// The head's scale, for the reveal's build-up pulses.
        var scale: CGFloat = 1
        /// How far above its spot the pin floats, for the reveal's drop.
        var lift: CGFloat = 0
        /// The verdict's gold ring, 0 to 1, or nil.
        var ring: CGFloat?
        /// How many rounds the pin stands for, on a clustered map. Above 1 it shows a count.
        var count = 1
        /// What VoiceOver reads for a pin that is a button.
        var label: String?
    }

    /// The great-circle line from the guess toward the real spot. `progress` is how
    /// much of it is drawn, 0 to 1.
    struct Line {
        let from: GuessMySpotCoordinate
        let to: GuessMySpotCoordinate
        var progress: Double = 1
        /// A far guess draws a quiet dashed line instead of the gold one.
        var isFar = false
    }

    @Binding var position: MapCameraPosition
    var pins: [Pin] = []
    var line: Line?
    /// What a tap does. Nil: taps do nothing.
    var onTap: ((GuessMySpotCoordinate) -> Void)?
    /// False for a map that only shows, such as the reveal while it plays.
    var isInteractive = true
    var showsSatelliteButton = true
    /// Makes each pin a button that reports its id, as on "Our guesses".
    var onPinTap: ((String) -> Void)?
    /// Where the camera settled after each move.
    var onCameraChange: ((MapCameraUpdateContext) -> Void)?
    var accessibilityValue: LocalizedStringResource = .guessMySpotMapNoPin
    /// The satellite choice for this screen alone, as the reveal's landing sets it.
    /// Nil: the saved choice, which the button changes.
    var satellite: Binding<Bool>?
    /// `.realistic` lets the camera back off to the globe, as the reveal's overview of a far guess does.
    var elevation: MapStyle.Elevation = .flat

    static let satelliteKey = "paeonia.games.guessMySpot.satellite"
    @AppStorage(GuessMySpotMap.satelliteKey) private var savedSatellite = false
    @State private var center: CLLocationCoordinate2D?
    /// Where the map sits in its window, and the safe area under it.
    @State private var layoutFrame: CGRect = .zero
    @State private var bottomInset: CGFloat = 0
    /// The map as it looked before the style switched. It fades out over the new style,
    /// so the switch dissolves instead of cutting while the new images load.
    @State private var styleCover: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: isInteractive ? [.pan, .zoom] : []) {
                if let line, line.progress > 0 {
                    lineContent(line)
                }
                ForEach(pins) { pin in
                    Annotation("", coordinate: pin.coordinate.location, anchor: .bottom) {
                        pinView(pin)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(mapStyle)
            // No safe area padding here: a map that opens cold draws inside its padding
            // for its first frames and jumps when it grows. The cameras leave the room.
            .mapControls {}
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
                onCameraChange?(context)
            }
            .onTapGesture(coordinateSpace: .local) { point in
                guard let onTap, let coordinate = proxy.convert(point, from: .local) else { return }
                dropped(at: GuessMySpotCoordinate(coordinate), onTap)
            }
        }
        .overlay(alignment: .top) {
            if let styleCover {
                Image(uiImage: styleCover)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    // A hole where the button is, so the button's glass doesn't show the old one.
                    .mask {
                        Rectangle()
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .opacity(showsSatelliteButton ? 1 : 0)
                                    .frame(width: 44, height: 44)
                                    .padding(PaeoniaSpacing.space8)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { layoutFrame = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .overlay(alignment: .topTrailing) {
            if showsSatelliteButton {
                satelliteButton
                    .transition(.opacity)
            }
        }
        .animation(PaeoniaMotion.stateChange, value: showsSatelliteButton)
        // From the button or the reveal's landing. The map on screen still shows the old style here.
        .onChange(of: isSatellite) { coverStyleSwitch() }
        .accessibilityElement(children: onPinTap == nil ? .ignore : .contain)
        .accessibilityLabel(Text(.guessMySpotMapA11Y))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityActions {
            if let onTap {
                Button {
                    guard let center else { return }
                    dropped(at: GuessMySpotCoordinate(center), onTap)
                } label: {
                    Text(.guessMySpotMapDropCenter)
                }
            }
        }
    }

    @ViewBuilder
    private func pinView(_ pin: Pin) -> some View {
        if let onPinTap {
            Button {
                PaeoniaHaptics.selection()
                GameSound.tap.play(volume: 0.6)
                onPinTap(pin.id)
            } label: {
                pinMark(pin)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: pin.label ?? ""))
        } else {
            pinMark(pin)
        }
    }

    private func pinMark(_ pin: Pin) -> some View {
        GuessMySpotPin(
            style: pin.style, scale: pin.scale, glow: pin.glow, lift: pin.lift, ring: pin.ring, count: pin.count
        )
        .opacity(pin.opacity)
    }

    private var isSatellite: Bool {
        satellite?.wrappedValue ?? savedSatellite
    }

    private var mapStyle: MapStyle {
        isSatellite
            ? .hybrid(elevation: elevation, pointsOfInterest: .excludingAll)
            : .standard(elevation: elevation, emphasis: .muted, pointsOfInterest: .excludingAll)
    }

    private func dropped(at coordinate: GuessMySpotCoordinate, _ onTap: (GuessMySpotCoordinate) -> Void) {
        guard GuessMySpotRules.isValid(coordinate) else { return }
        PaeoniaHaptics.selection()
        GameSound.tap.play(volume: 0.6)
        onTap(coordinate)
    }

    @MapContentBuilder
    private func lineContent(_ line: Line) -> some MapContent {
        let tip = GuessMySpotRules.intermediate(from: line.from, to: line.to, fraction: min(1, line.progress))
        let coordinates = [line.from.location, tip.location]
        if line.isFar {
            MapPolyline(coordinates: coordinates, contourStyle: .geodesic)
                .stroke(Color.paeoniaTextSecondary, style: StrokeStyle(lineWidth: 4, lineCap: .butt, dash: [6, 7]))
        } else {
            MapPolyline(coordinates: coordinates, contourStyle: .geodesic)
                .stroke(Color.paeoniaInkGold.opacity(0.3), style: StrokeStyle(lineWidth: 12, lineCap: .butt))
            MapPolyline(coordinates: coordinates, contourStyle: .geodesic)
                .stroke(Color.paeoniaInkGold, style: StrokeStyle(lineWidth: 4, lineCap: .butt))
        }
    }

    private var satelliteButton: some View {
        Button {
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.5)
            withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) {
                if let satellite {
                    satellite.wrappedValue.toggle()
                } else {
                    savedSatellite.toggle()
                }
            }
        } label: {
            // The style the map shows now.
            Image(systemName: isSatellite ? "globe.europe.africa.fill" : "map.fill")
                .contentTransition(.symbolEffect(.replace))
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.6)), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(PaeoniaSpacing.space8)
        .accessibilityLabel(Text(.guessMySpotMapSatellite))
        .accessibilityAddTraits(isSatellite ? [.isToggle, .isSelected] : .isToggle)
        .accessibilityIdentifier("guessMySpot.map.satellite")
    }
}

extension GuessMySpotMap {
    /// Lays the map as it looked over the new style and fades it out, so a style
    /// switch dissolves instead of showing gray while the new images load.
    private func coverStyleSwitch() {
        guard !reduceMotion, let cover = snapshot() else { return }
        styleCover = cover
        Task {
            // A moment for the new style's first images to draw.
            try? await Task.sleep(for: .milliseconds(100))
            guard styleCover === cover else { return }
            withAnimation(.easeInOut(duration: 0.3)) { styleCover = nil }
        }
    }

    /// The map as it is on screen now, cut from its window.
    private func snapshot() -> UIImage? {
        guard frame.width > 0, frame.height > 0, let window = Self.keyWindow else { return nil }
        return UIGraphicsImageRenderer(bounds: frame).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    /// Where the map draws in its window, for the picture of it a style switch fades out.
    private var frame: CGRect {
        Self.drawnFrame(layoutFrame, bottomInset: bottomInset)
    }

    /// Where a map whose frame is `frame` draws. MapKit draws on through the safe area
    /// under it, `bottomInset` tall, such as under a bottom bar and the home indicator.
    static func drawnFrame(_ frame: CGRect, bottomInset: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height + max(0, bottomInset))
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

/// Where the map's camera goes.
enum GuessMySpotCamera {
    /// The whole world, so the guess map gives no hint of a region.
    static var world: MapCameraPosition { .rect(MKMapRect.world) }

    /// About `meters` across, centered on `spot`.
    static func around(_ spot: GuessMySpotCoordinate, meters: Double) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: spot.location, latitudinalMeters: meters, longitudinalMeters: meters))
    }

    /// `position` fitted inside `insets` of a map `size` points big, given as the rect
    /// of the whole map. The reveal frames its camera this way instead of with safe
    /// area padding, because a new map draws inside its padding for its first frames
    /// and jumps when it grows, and a padding that changes moves the camera.
    /// `maxScale` caps the map points per screen point, for a target wider than
    /// MapKit zooms out. The target's middle then still sits in the middle of the insets.
    static func filling(
        _ position: MapCameraPosition,
        size: CGSize,
        insets: EdgeInsets,
        maxScale: Double = .infinity
    ) -> MapCameraPosition {
        guard let target = position.rect ?? position.region.map(mapRect), size.width > 0, size.height > 0
        else { return position }
        let width = max(1, size.width - insets.leading - insets.trailing)
        let height = max(1, size.height - insets.top - insets.bottom)
        // Map points per screen point, so the whole target fits.
        let scale = min(maxScale, max(target.width / width, target.height / height))
        return .rect(MKMapRect(
            x: target.midX - (insets.leading + width / 2) * scale,
            y: target.midY - (insets.top + height / 2) * scale,
            width: size.width * scale,
            height: size.height * scale
        ))
    }

    /// The rect a map at `frame` shows when it lines up point for point with another
    /// map at `source` that showed `rect`, both frames on the same screen.
    static func continuing(_ rect: MKMapRect, from source: CGRect, to frame: CGRect) -> MapCameraPosition {
        let scale = rect.width / max(1, source.width)
        return .rect(MKMapRect(
            x: rect.minX + (frame.minX - source.minX) * scale,
            y: rect.minY + (frame.minY - source.minY) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        ))
    }

    /// A region's box in map points, measured from its center so it never wraps at the 180th meridian.
    private static func mapRect(_ region: MKCoordinateRegion) -> MKMapRect {
        let center = MKMapPoint(region.center)
        let latitude = region.center.latitude, longitude = region.center.longitude
        let half = region.span.latitudeDelta / 2
        let north = MKMapPoint(CLLocationCoordinate2D(latitude: min(85, latitude + half), longitude: longitude))
        let south = MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, latitude - half), longitude: longitude))
        let width = MKMapSize.world.width * region.span.longitudeDelta / 360
        return MKMapRect(x: center.x - width / 2, y: north.y, width: width, height: south.y - north.y)
    }

    /// Both spots with room around them. Across the 180th meridian the box goes the short way.
    static func framing(
        _ guess: GuessMySpotCoordinate,
        _ spot: GuessMySpotCoordinate,
        padding: Double = 0.9
    ) -> MapCameraPosition {
        let first = MKMapPoint(guess.location)
        var second = MKMapPoint(spot.location)
        let worldWidth = MKMapSize.world.width
        if second.x - first.x > worldWidth / 2 {
            second.x -= worldWidth
        } else if first.x - second.x > worldWidth / 2 {
            second.x += worldWidth
        }
        var rect = MKMapRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(first.x - second.x),
            height: abs(first.y - second.y)
        )
        // A guess right on the spot still shows a few hundred metres around it.
        let minimum = MKMapPointsPerMeterAtLatitude(spot.latitude) * 800
        let side = max(rect.width, rect.height, minimum)
        rect = rect.insetBy(
            dx: -(side - rect.width) / 2 - side * padding / 2,
            dy: -(side - rect.height) / 2 - side * padding / 2
        )
        return .rect(rect)
    }

    /// Every spot with room around them, such as all the pins of "Our guesses".
    /// ponytail: a plain bounding box, so pins on both sides of the 180th meridian frame the long way.
    /// `minimumMeters` keeps a few close spots from filling the screen. Opening a
    /// cluster passes a small one, so the zoom goes far enough to split it.
    static func framing(_ spots: [GuessMySpotCoordinate], minimumMeters: Double = 20_000) -> MapCameraPosition {
        guard let first = spots.first else { return world }
        guard spots.count > 1 else { return around(first, meters: 50_000) }
        let points = spots.map { MKMapPoint($0.location) }
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        let side = max(maxX - minX, maxY - minY, MKMapPointsPerMeterAtLatitude(first.latitude) * minimumMeters)
        let rect = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -(side - (maxX - minX)) / 2 - side * 0.15, dy: -(side - (maxY - minY)) / 2 - side * 0.15)
        return .rect(rect)
    }

    /// The landing on the real spot: centered on it and close enough to see the
    /// streets around it, however far the guess was. A guess within 1 km stays in
    /// view, and a close one fills it, down to 150 m across.
    static func landing(on spot: GuessMySpotCoordinate, guess: GuessMySpotCoordinate) -> MapCameraPosition {
        let center = MKMapPoint(spot.location)
        var point = MKMapPoint(guess.location)
        let worldWidth = MKMapSize.world.width
        if point.x - center.x > worldWidth / 2 {
            point.x -= worldWidth
        } else if center.x - point.x > worldWidth / 2 {
            point.x += worldWidth
        }
        let perMeter = MKMapPointsPerMeterAtLatitude(spot.latitude)
        // The guess sits inside the middle 85 percent of the view. Each side on its
        // own, so a guess beside the spot fills a wide view instead of a square one.
        func side(_ offset: Double) -> Double {
            min(max(150 * perMeter, 2 * offset / 0.85), 2_400 * perMeter)
        }
        let width = side(abs(point.x - center.x))
        let height = side(abs(point.y - center.y))
        return .rect(MKMapRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
    }
}

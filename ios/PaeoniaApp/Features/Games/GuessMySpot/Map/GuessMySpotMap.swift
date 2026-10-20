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
    var onCameraChange: ((MKCoordinateRegion) -> Void)?
    var accessibilityValue: LocalizedStringResource = .guessMySpotMapNoPin

    @AppStorage("paeonia.games.guessMySpot.satellite") private var isSatellite = false
    @State private var center: CLLocationCoordinate2D?
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
            // Room for a pin's head above its foot, so a pin framed near the top edge isn't cut off.
            .safeAreaPadding(.top, GuessMySpotPin.headSize)
            .mapControls {}
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
                onCameraChange?(context.region)
            }
            .onTapGesture(coordinateSpace: .local) { point in
                guard let onTap, let coordinate = proxy.convert(point, from: .local) else { return }
                dropped(at: GuessMySpotCoordinate(coordinate), onTap)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsSatelliteButton {
                satelliteButton
                    .transition(.opacity)
            }
        }
        .animation(PaeoniaMotion.stateChange, value: showsSatelliteButton)
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

    private var mapStyle: MapStyle {
        isSatellite
            ? .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
            : .standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)
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
                isSatellite.toggle()
            }
        } label: {
            Image(systemName: isSatellite ? "map.fill" : "globe.europe.africa.fill")
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.6)), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(PaeoniaSpacing.space8)
        .accessibilityLabel(Text(isSatellite ? .guessMySpotMapStandard : .guessMySpotMapSatellite))
        .accessibilityIdentifier("guessMySpot.map.satellite")
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

    /// The landing on the real spot: centered on it, close enough to see the place,
    /// with the guess still in view. Nil when that would be more than 400 km across,
    /// as for a far guess, which stays on the view of both spots.
    static func landing(on spot: GuessMySpotCoordinate, guess: GuessMySpotCoordinate) -> MapCameraPosition? {
        let metersPerDegree = 111_320.0
        let north = abs(guess.latitude - spot.latitude) * metersPerDegree
        var degreesEast = abs(guess.longitude - spot.longitude)
        if degreesEast > 180 { degreesEast = 360 - degreesEast }
        let east = degreesEast * metersPerDegree * cos(spot.latitude * .pi / 180)
        // The guess sits inside the middle 85 percent of the view.
        let latitudeMeters = max(500, 2 * north / 0.85)
        let longitudeMeters = max(500, 2 * east / 0.85)
        guard max(latitudeMeters, longitudeMeters) <= 400_000 else { return nil }
        return .region(MKCoordinateRegion(
            center: spot.location,
            latitudinalMeters: latitudeMeters,
            longitudinalMeters: longitudeMeters
        ))
    }
}

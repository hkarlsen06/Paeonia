import MapKit
import SwiftUI

/// Where the camera is while it flies. Apart from the reveal's own state, so each
/// frame of a flight redraws the backdrop alone and not the whole reveal and its map.
@MainActor
@Observable
final class GuessMySpotFlightPosition {
    var rect: MKMapRect?
    /// How soft the pictures are. Blown up past their size, labels and all, they read as motion when soft.
    var blur: CGFloat = 0
}

/// A flight's pictures lined up with the camera as it moves, each closer one over
/// the wider ones so the picture is as sharp as it can be.
///
/// When every view of a flight has drawn, the flight is all pictures. The map
/// jumps to the end of the flight under them, so it spends the whole flight
/// loading that one view instead of every view on the way, and the pictures fade
/// once it has. The backdrop then draws the pins and the line itself, over the
/// pictures, where the map would.
///
/// Otherwise the zoom out shows the map where it already has its images (`loaded`)
/// and the pictures cover the gray around it while the map loads the wider view.
/// Then they are over the map's line too, so the line starts drawing once they have faded.
struct GuessMySpotFlightBackdrop: View {
    /// The flight's views, drawn ahead by the preloader, from the widest to the closest.
    struct Pictures {
        let pictures: [GuessMySpotMapPreloader.Picture]
        /// The part of the map the camera had loaded when the zoom out began, which
        /// shows through. Nil: the pictures cover the whole map.
        let loaded: MKMapRect?
        var opacity: Double = 1
    }

    let pictures: Pictures
    let position: GuessMySpotFlightPosition
    /// How big the map draws, past its frame at the bottom.
    let size: CGSize
    /// The map's pins and line, drawn over pictures that cover the whole map.
    var pins: [GuessMySpotMap.Pin] = []
    var line: GuessMySpotMap.Line?

    var body: some View {
        if let view = position.rect {
            ZStack(alignment: .topLeading) {
                Group {
                    covered(view)
                    if pictures.loaded == nil, let line { lineMark(line, view: view) }
                }
                .opacity(pictures.opacity)
                // The pins stay while the pictures fade: MapKit fades its own back in after the camera jumps.
                if pictures.loaded == nil {
                    ForEach(pins) { pin in
                        let point = onScreen(MKMapPoint(pin.coordinate.location), view: view)
                        GuessMySpotPin(
                            style: pin.style, scale: pin.scale, glow: pin.glow, lift: pin.lift, ring: pin.ring
                        )
                        .opacity(pin.opacity)
                        // The pin's foot on its spot, as the map's annotation stands.
                        .position(x: point.x, y: point.y - GuessMySpotPin.height / 2)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func covered(_ view: MKMapRect) -> some View {
        let stack = ZStack(alignment: .topLeading) {
            ForEach(pictures.pictures.indices, id: \.self) { index in
                let picture = pictures.pictures[index], frame = onScreen(picture.rect, view: view)
                Image(uiImage: picture.image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    // A closer picture shows once it is big enough to stand for the one under it.
                    // Satellite colors change between zoom levels, so a small one read as a box.
                    .opacity(index == 0 ? 1 : min(1, max(0, (frame.width / size.width - 0.25) / 0.35)))
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .blur(radius: position.blur, opaque: true)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        if let loaded = pictures.loaded {
            let hole = onScreen(loaded, view: view)
            stack.mask {
                Rectangle()
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .frame(width: hole.width, height: hole.height)
                            .offset(x: hole.minX, y: hole.minY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
        } else {
            stack
        }
    }

    /// The great-circle line as the map draws it (`GuessMySpotMap.lineContent`).
    @ViewBuilder
    private func lineMark(_ line: GuessMySpotMap.Line, view: MKMapRect) -> some View {
        let path = linePath(line, view: view)
        if line.isFar {
            path.stroke(Color.paeoniaTextSecondary, style: StrokeStyle(lineWidth: 4, lineCap: .butt, dash: [6, 7]))
        } else {
            path.stroke(Color.paeoniaInkGold.opacity(0.3), style: StrokeStyle(lineWidth: 12, lineCap: .butt))
            path.stroke(Color.paeoniaInkGold, style: StrokeStyle(lineWidth: 4, lineCap: .butt))
        }
    }

    private func linePath(_ line: GuessMySpotMap.Line, view: MKMapRect) -> Path {
        let progress = min(1, line.progress)
        var points: [MKMapPoint] = []
        for fraction in Self.lineFractions {
            let coordinate = GuessMySpotRules.intermediate(from: line.from, to: line.to, fraction: fraction * progress)
            var point = MKMapPoint(coordinate.location)
            // Across the 180th meridian, on from the point before.
            if let previous = points.last {
                point.x += ((previous.x - point.x) / MKMapSize.world.width).rounded() * MKMapSize.world.width
            }
            points.append(point)
        }
        // The whole line moved by world widths so its end is the copy of the tip nearest the view.
        guard let last = points.last else { return Path() }
        let shift = ((view.midX - last.x) / MKMapSize.world.width).rounded() * MKMapSize.world.width
        return Path { path in
            path.addLines(points.map { onScreen(MKMapPoint(x: $0.x + shift, y: $0.y), view: view) })
        }
    }

    /// Where along the line its points go: even steps, and closer and closer toward
    /// both ends. A close camera sees only a few hundred metres by a pin, and short
    /// pieces there follow the great circle and keep their numbers on screen small.
    private static let lineFractions: [Double] = {
        let even = (0...40).map { Double($0) / 40 }
        let ends = (1...30).flatMap { [pow(0.5, Double($0)), 1 - pow(0.5, Double($0))] }
        return Set(even + ends).sorted()
    }()

    private func onScreen(_ rect: MKMapRect, view: MKMapRect) -> CGRect {
        let scale = size.width / max(1, view.width)
        return CGRect(
            x: (rect.minX - view.minX) * scale,
            y: (rect.minY - view.minY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    /// `point` on screen, from its copy nearest the view across the 180th meridian.
    private func onScreen(_ point: MKMapPoint, view: MKMapRect) -> CGPoint {
        let world = MKMapSize.world.width
        let x = point.x + ((view.midX - point.x) / world).rounded() * world
        let scale = size.width / max(1, view.width)
        return CGPoint(x: (x - view.minX) * scale, y: (point.y - view.minY) * scale)
    }
}

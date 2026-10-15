import SwiftUI

extension View {
    /// Sizes a layer to the board face and puts it below the hover lane.
    func placedOnBoard(_ geometry: ConnectFourBoardGeometry) -> some View {
        frame(width: geometry.width, height: geometry.boardHeight)
            .padding(.top, geometry.laneHeight)
    }
}

/// The dark panel behind the discs. Empty holes show it.
struct ConnectFourBoardBacking: View {
    let geometry: ConnectFourBoardGeometry

    var body: some View {
        RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
            .fill(Color.paeoniaBackgroundSecondary)
            .shadow(color: Color.black.opacity(0.4), radius: 14, y: 8)
            .placedOnBoard(geometry)
    }
}

/// The plum face of the board with a hole for every cell, a soft shadow inside
/// each hole, and a light edge along the top. Discs sit behind it, so a disc
/// shows only through the holes.
struct ConnectFourBoardFace: View {
    let geometry: ConnectFourBoardGeometry

    var body: some View {
        ZStack {
            ConnectFourFacePath(geometry: geometry, cornerRadius: PaeoniaRadius.radius20)
                .fill(
                    LinearGradient(
                        colors: [.paeoniaSurfacePressed, .paeoniaSurfacePrimary],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: FillStyle(eoFill: true)
                )
            ConnectFourHoleShadows(geometry: geometry)
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.paeoniaAccentPrimary.opacity(0.5), .paeoniaAccentPrimary.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.25
                )
        }
        .placedOnBoard(geometry)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The face as one path. Filled with the even-odd rule, the holes are see-through.
nonisolated private struct ConnectFourFacePath: Shape {
    let geometry: ConnectFourBoardGeometry
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        for row in 0..<ConnectFourBoardGeometry.rows {
            for column in 0..<ConnectFourBoardGeometry.columns {
                path.addEllipse(in: geometry.holeRect(row: row, column: column))
            }
        }
        return path
    }
}

/// A shadow that falls from the top rim of each hole, plus a thin dark ring on
/// the rim. It draws over the discs, so a disc looks set into the board.
struct ConnectFourHoleShadows: View {
    let geometry: ConnectFourBoardGeometry

    private static let shadow = Gradient(stops: [
        .init(color: Color.black.opacity(0), location: 0.6),
        .init(color: Color.black.opacity(0.22), location: 0.88),
        .init(color: Color.black.opacity(0.45), location: 1),
    ])

    var body: some View {
        Canvas { context, _ in
            for row in 0..<ConnectFourBoardGeometry.rows {
                for column in 0..<ConnectFourBoardGeometry.columns {
                    drawShadow(in: &context, rect: geometry.holeRect(row: row, column: column))
                }
            }
        }
    }

    private func drawShadow(in context: inout GraphicsContext, rect: CGRect) {
        // The gradient's center sits a little low, so the top rim is the darkest.
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.12)
        let hole = Path(ellipseIn: rect)
        context.fill(
            hole,
            with: .radialGradient(Self.shadow, center: center, startRadius: 0, endRadius: rect.width / 2)
        )
        context.stroke(hole, with: .color(Color.paeoniaBackgroundSecondary.opacity(0.75)), lineWidth: 1.5)
    }
}

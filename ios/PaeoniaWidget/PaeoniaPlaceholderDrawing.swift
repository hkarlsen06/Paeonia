import SwiftUI

struct PaeoniaPlaceholderDrawing: View {
    private let primaryStrokePoints = [
        CGPoint(x: 0.12, y: 0.58),
        CGPoint(x: 0.24, y: 0.34),
        CGPoint(x: 0.40, y: 0.46),
        CGPoint(x: 0.53, y: 0.24),
        CGPoint(x: 0.73, y: 0.42),
        CGPoint(x: 0.88, y: 0.28),
    ]
    private let secondaryStrokePoints = [
        CGPoint(x: 0.18, y: 0.74),
        CGPoint(x: 0.34, y: 0.64),
        CGPoint(x: 0.49, y: 0.76),
        CGPoint(x: 0.66, y: 0.58),
        CGPoint(x: 0.84, y: 0.66),
    ]

    var body: some View {
        GeometryReader { proxy in
            drawing(in: proxy.size)
        }
        .padding(PaeoniaWidgetSpacing.space12)
    }

    private func drawing(in size: CGSize) -> some View {
        ZStack {
            PaeoniaSketchStroke(points: primaryStrokePoints)
                .stroke(.paeoniaWidgetDrawing, style: primaryStrokeStyle(in: size))

            PaeoniaSketchStroke(points: secondaryStrokePoints)
                .stroke(
                    .paeoniaWidgetAccentSecondary.opacity(0.82),
                    style: secondaryStrokeStyle(in: size)
                )

            Circle()
                .fill(.paeoniaWidgetAccentPrimary)
                .frame(width: dotSize(in: size), height: dotSize(in: size))
                .position(x: size.width * 0.80, y: size.height * 0.29)
        }
        .frame(width: size.width, height: size.height)
    }

    private func primaryStrokeStyle(in size: CGSize) -> StrokeStyle {
        StrokeStyle(
            lineWidth: strokeWidth(in: size),
            lineCap: .round,
            lineJoin: .round
        )
    }

    private func secondaryStrokeStyle(in size: CGSize) -> StrokeStyle {
        StrokeStyle(
            lineWidth: strokeWidth(in: size) * 0.7,
            lineCap: .round,
            lineJoin: .round
        )
    }

    private func strokeWidth(in size: CGSize) -> CGFloat {
        max(5, min(size.width, size.height) * 0.055)
    }

    private func dotSize(in size: CGSize) -> CGFloat {
        max(8, min(size.width, size.height) * 0.1)
    }
}

private struct PaeoniaSketchStroke: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let firstPoint = points.first else {
            return path
        }

        path.move(to: point(firstPoint, in: rect))

        for nextPoint in points.dropFirst() {
            path.addLine(to: point(nextPoint, in: rect))
        }

        return path
    }

    private func point(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + rect.width * point.x,
            y: rect.minY + rect.height * point.y
        )
    }
}

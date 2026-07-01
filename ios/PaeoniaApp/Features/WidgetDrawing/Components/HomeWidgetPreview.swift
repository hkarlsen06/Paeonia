import SwiftUI
import UIKit

/// Reads the same App Group payload the Home Screen widget renders so the home
/// screen can show an exact preview of what the couple's widget currently looks
/// like. This is read-only local cache; it never touches canonical drawing data.
nonisolated struct HomeWidgetPreviewLoader {
    struct Content: Equatable {
        /// The rendered preview image, when a normal (non-redacted) drawing has
        /// been saved. `nil` means there is nothing to show yet, so the caller
        /// falls back to the placeholder sketch.
        var image: UIImage?
    }

    let containerURL: URL?
    let payloadPath: String

    init(
        containerURL: URL? = PaeoniaAppGroup.containerURL,
        payloadPath: String = PaeoniaAppGroup.widgetPayloadPath
    ) {
        self.containerURL = containerURL
        self.payloadPath = payloadPath
    }

    func load() -> Content {
        guard let containerURL else {
            return Content(image: nil)
        }

        let payloadURL = containerURL.appendingPathComponent(payloadPath)
        guard let data = try? Data(contentsOf: payloadURL),
              let payload = try? Self.decoder().decode(WidgetSharePayload.self, from: data) else {
            return Content(image: nil)
        }

        // Honour the same privacy gate the widget uses: a redacted payload must
        // never surface the drawing, even inside the app.
        guard payload.privacyMode == .normal, !payload.isRedacted else {
            return Content(image: nil)
        }

        guard let relativePath = Self.preferredPreviewPath(in: payload.previews) else {
            return Content(image: nil)
        }

        let imageURL = containerURL.appendingPathComponent(relativePath)
        return Content(image: UIImage(contentsOfFile: imageURL.path))
    }

    /// Prefers the small preview (closest to the in-app card size) and falls back
    /// to any available rendition.
    static func preferredPreviewPath(in previews: [String: String]) -> String? {
        previews["systemSmall"] ?? previews["systemLarge"] ?? previews.values.sorted().first
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@MainActor
@Observable
final class HomeWidgetPreviewModel {
    private(set) var image: UIImage?

    private let loader: HomeWidgetPreviewLoader

    init(loader: HomeWidgetPreviewLoader = HomeWidgetPreviewLoader()) {
        self.loader = loader
    }

    // The payload is a tiny JSON file plus a small PNG, so reading it directly
    // is cheap enough to do without hopping off the main actor.
    func reload() {
        image = loader.load().image
    }
}

/// A compact, tappable rendering of the couple's Home Screen widget shown on the
/// app's home screen. Tapping it opens the full drawing screen.
struct HomeWidgetCard: View {
    let onOpen: () -> Void

    @State private var model = HomeWidgetPreviewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onOpen) {
            widget
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.homeWidgetCardLabel))
        .accessibilityHint(Text(.homeWidgetCardHint))
        .accessibilityAddTraits(.isButton)
        .task {
            model.reload()
        }
        // Refresh the preview the moment a sync writes a new payload, instead of
        // waiting for this card to reappear (e.g. after visiting the drawing
        // screen).
        .onReceive(NotificationCenter.default.publisher(for: .paeoniaWidgetCanvasDidUpdate)) { _ in
            model.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reload()
            }
        }
    }

    private var widget: some View {
        VStack(alignment: .center, spacing: PaeoniaSpacing.space12) {
            drawingSurface
                // Crossfade between the placeholder sketch and the real drawing
                // when the image first arrives or changes. The frame is already
                // fixed by the parent's aspectRatio, so this is a content swap,
                // not a layout shift. Instant under Reduce Motion.
                .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: model.image == nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: PaeoniaSpacing.space4) {
                Image(systemName: "pencil.tip.crop.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)

                Text(.homeWidgetCta)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
            }
            .foregroundStyle(.paeoniaAccentPrimary)
        }
        // Match the map tile's distance label: same bottom inset so the two CTAs
        // line up vertically across the side-by-side tiles.
        .padding([.top, .horizontal], PaeoniaSpacing.space16)
        .padding(.bottom, PaeoniaSpacing.tileCaptionBottomInset)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(.paeoniaBackgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous)
                .stroke(.paeoniaSurfacePressed, lineWidth: PaeoniaRadius.strokeDefault)
        }
        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }

    @ViewBuilder
    private var drawingSurface: some View {
        if let image = model.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
                .transition(.opacity)
        } else {
            HomeWidgetPlaceholderSketch()
                .transition(.opacity)
        }
    }
}

/// A lightweight sketch shown before the couple has saved a drawing, mirroring
/// the placeholder the Home Screen widget renders.
private struct HomeWidgetPlaceholderSketch: View {
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
            sketch(in: proxy.size)
        }
        .accessibilityHidden(true)
    }

    private func sketch(in size: CGSize) -> some View {
        ZStack {
            HomeWidgetSketchStroke(points: primaryStrokePoints)
                .stroke(.paeoniaWidgetDrawing, style: strokeStyle(in: size, ratio: 1))

            HomeWidgetSketchStroke(points: secondaryStrokePoints)
                .stroke(.paeoniaAccentSecondary.opacity(0.82), style: strokeStyle(in: size, ratio: 0.7))

            Circle()
                .fill(.paeoniaAccentPrimary)
                .frame(width: dotSize(in: size), height: dotSize(in: size))
                .position(x: size.width * 0.80, y: size.height * 0.29)
        }
        .frame(width: size.width, height: size.height)
    }

    private func strokeStyle(in size: CGSize, ratio: CGFloat) -> StrokeStyle {
        StrokeStyle(
            lineWidth: max(4, min(size.width, size.height) * 0.05) * ratio,
            lineCap: .round,
            lineJoin: .round
        )
    }

    private func dotSize(in size: CGSize) -> CGFloat {
        max(7, min(size.width, size.height) * 0.09)
    }
}

private struct HomeWidgetSketchStroke: Shape {
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

#if DEBUG
#Preview {
    HomeWidgetCard(onOpen: {})
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
        .preferredColorScheme(.dark)
}
#endif

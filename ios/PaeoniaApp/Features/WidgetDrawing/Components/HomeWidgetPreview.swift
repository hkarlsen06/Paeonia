import SwiftUI
import UIKit

/// Reads the same App Group payload the Home Screen widget renders so the home
/// screen can show the same square drawing in its compact feature tile. This is
/// read-only local cache; it never touches canonical drawing data.
nonisolated struct HomeWidgetPreviewLoader {
    struct Content: Equatable {
        /// The rendered preview image, when a normal (non-redacted) drawing has
        /// been saved. `nil` means there is nothing to show yet, so the caller
        /// falls back to the placeholder sketch.
        var image: UIImage?
        var authorName: String?
        var savedAt: Date?
        var isRedacted = false
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
            return Content(image: nil, authorName: nil, savedAt: nil)
        }

        let payloadURL = containerURL.appendingPathComponent(payloadPath)
        guard let data = try? Data(contentsOf: payloadURL),
              let payload = try? Self.decoder().decode(WidgetSharePayload.self, from: data),
              payload.schemaVersion == WidgetSharePayload.currentSchemaVersion,
              payload.rendererVersion == WidgetSharePayload.currentRendererVersion
        else {
            return Content(image: nil, authorName: nil, savedAt: nil)
        }

        // Honour the same privacy gate the widget uses: a redacted payload must
        // never surface the drawing, even inside the app.
        guard payload.privacyMode == .normal, !payload.isRedacted else {
            return Content(image: nil, authorName: nil, savedAt: nil, isRedacted: true)
        }

        guard !payload.contentHash.isEmpty,
              let relativePath = Self.preferredPreviewPath(in: payload.previews),
              Self.isSafeRelativePath(relativePath)
        else {
            return Content(image: nil, authorName: nil, savedAt: nil)
        }

        let imageURL = containerURL.appendingPathComponent(relativePath)
        guard let image = UIImage(contentsOfFile: imageURL.path) else {
            return Content(image: nil, authorName: nil, savedAt: nil)
        }
        return Content(
            image: image,
            authorName: payload.authorName?.trimmedNonEmpty,
            savedAt: payload.createdAt
        )
    }

    /// Prefers the small preview (closest to the in-app card size) and falls back
    /// to any available rendition.
    static func preferredPreviewPath(in previews: [String: String]) -> String? {
        previews["systemSmall"] ?? previews["systemLarge"] ?? previews.values.sorted().first
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
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
    private(set) var content = HomeWidgetPreviewLoader.Content(
        image: nil,
        authorName: nil,
        savedAt: nil
    )

    private let loader: HomeWidgetPreviewLoader

    init(loader: HomeWidgetPreviewLoader = HomeWidgetPreviewLoader()) {
        self.loader = loader
    }

    // The payload is a tiny JSON file plus a small PNG, so reading it directly
    // is cheap enough to do without hopping off the main actor.
    func reload() {
        content = loader.load()
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
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            header
            drawingSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .padding(PaeoniaSpacing.space12)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: model.content.image == nil)
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

    private var header: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            PaeoniaWordmark(size: 14)
                .layoutPriority(1)
            Spacer(minLength: PaeoniaSpacing.space4)
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space4) {
            footerTitle
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)

            Spacer(minLength: PaeoniaSpacing.space4)

            if let savedAt = model.content.savedAt {
                Text(Self.timestampText(savedAt))
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(1)
            } else {
                Text(.homeWidgetCta)
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .foregroundStyle(.paeoniaAccentPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    @ViewBuilder
    private var footerTitle: some View {
        if let authorName = model.content.authorName {
            Text(verbatim: authorName)
        } else {
            Text(.widgetDrawingTitle)
        }
    }

    private static func timestampText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    @ViewBuilder
    private var drawingSurface: some View {
        Group {
            if let image = model.content.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else if model.content.isRedacted {
                VStack(spacing: PaeoniaSpacing.space8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.paeoniaAccentPrimary)
                    Text(.widgetDrawingTitle)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HomeWidgetPlaceholderSketch()
                    .transition(.opacity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
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

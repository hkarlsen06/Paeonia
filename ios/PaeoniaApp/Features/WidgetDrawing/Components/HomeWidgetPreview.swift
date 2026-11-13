import PencilKit
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
        /// The revision the shown drawing came from, for putting a reaction on it.
        var revisionID: String?
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
            savedAt: payload.createdAt,
            revisionID: payload.revisionID
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
    let coupleID: UUID?
    let partnerName: String?
    let onOpen: () -> Void

    @State private var model = HomeWidgetPreviewModel()
    /// Shows the partner's canvas while they draw on it. Nil without a couple.
    /// Built when the card first appears, since `init` runs on every Home update.
    @State private var live: WidgetLiveDrawing?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(coupleID: UUID? = nil, partnerName: String? = nil, onOpen: @escaping () -> Void) {
        self.coupleID = coupleID
        self.partnerName = partnerName
        self.onOpen = onOpen
    }

    var body: some View {
        Button(action: onOpen) {
            widget
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.homeWidgetCardLabel))
        .accessibilityHint(Text(.homeWidgetCardHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.widgetDrawing")
        // Beside the card's button, not inside it, so a tap on the reaction does not open the drawing.
        // On the drawing's bottom corner, above the line under it.
        .overlay(alignment: Alignment(horizontal: .drawingTrailing, vertical: .drawingBottom)) {
            WidgetDrawingReactionControl(shownRevisionID: model.content.revisionID)
                .padding(PaeoniaSpacing.space4)
        }
        .task {
            model.reload()
            if live == nil, let coupleID {
                live = WidgetLiveDrawing(coupleID: coupleID, role: .watching)
            }
            live?.start()
        }
        .onDisappear {
            live?.stop()
        }
        // Refresh the preview the moment a sync writes a new payload, instead of
        // waiting for this card to reappear (e.g. after visiting the drawing
        // screen).
        .onReceive(NotificationCenter.default.publisher(for: .paeoniaWidgetCanvasDidUpdate)) { _ in
            model.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.reload()
                live?.start()
            case .background:
                live?.stop()
            default:
                break
            }
        }
    }

    /// Laid out like the calendar tile beside it: the drawing as an object with no tile around
    /// it, and one line under it, in the same square.
    private var widget: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            drawingSurface
                .shadow(color: PaeoniaTileTone.plain.shadow, radius: 18, x: 0, y: 10)
                .alignmentGuide(.drawingTrailing) { $0[.trailing] }
                .alignmentGuide(.drawingBottom) { $0[.bottom] }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            header
                .multilineTextAlignment(.center)
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: model.content.image == nil)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: live?.isShowingPartnerCanvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, PaeoniaSpacing.space8)
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
    }

    /// One short line, so the drawing keeps most of the tile. It shows the partner
    /// drawing, or who drew the saved picture and when, or a prompt to draw when
    /// nothing is saved yet. The generic widget title is left out because the tile
    /// itself already says what it is.
    @ViewBuilder
    private var header: some View {
        if live?.partnerActivity == .drawing, let partnerName {
            headerTitle(Text(.homeWidgetPartnerDrawing(partnerName)))
        } else if let savedAt = model.content.savedAt {
            HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space4) {
                if let authorName = model.content.authorName {
                    headerTitle(Text(verbatim: authorName))
                }
                Text(Self.timestampText(savedAt))
                    .font(.footnote)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        } else {
            Text(.homeWidgetCta)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
        }
    }

    private func headerTitle(_ text: Text) -> some View {
        text
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.paeoniaTextPrimary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
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
            if let live, live.isShowingPartnerCanvas {
                WidgetLiveOverlayView(live: live)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else if let image = model.content.image {
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
                        .accessibilityHidden(true)
                    Text(.widgetDrawingTitle)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The same sample drawing the Home Screen widget shows.
                Image(.placeholderSketch)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // A canvas, so the sample sketch and the hidden state don't float on the map.
        .background(.paeoniaBackgroundPrimary)
        .clipShape(DrawingCanvasShape())
        .overlay { DrawingCanvasShape().stroke(.paeoniaBorder, lineWidth: PaeoniaRadius.strokeDefault) }
    }
}

private extension HorizontalAlignment {
    enum DrawingTrailing: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.trailing] }
    }

    /// The drawing's trailing edge, which the reaction sits on.
    static let drawingTrailing = HorizontalAlignment(DrawingTrailing.self)
}

private extension VerticalAlignment {
    enum DrawingBottom: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.bottom] }
    }

    /// The drawing's bottom edge, which the reaction sits on.
    static let drawingBottom = VerticalAlignment(DrawingBottom.self)
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

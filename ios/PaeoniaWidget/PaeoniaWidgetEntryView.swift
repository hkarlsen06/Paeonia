import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct PaeoniaWidgetEntryView: View {
    let entry: PaeoniaWidgetEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        // System content margins (16 pt on iPhone, tighter on StandBy and the
        // Mac) frame the drawing like the widgets around it. The app name shows
        // under the widget, so there is no logo row and the drawing gets the room.
        VStack(alignment: .leading, spacing: PaeoniaWidgetSpacing.space8) {
            middleContent

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(PaeoniaWidgetURL.drawing)
        .accessibilityElement(children: .contain)
    }

    /// The square PencilKit raster sits centered on the plum widget background,
    /// with the metadata below it, so artwork never reads as a full-bleed
    /// background and metadata never floats over a stroke.
    @ViewBuilder
    private var middleContent: some View {
        PaeoniaWidgetDrawingArea {
            switch entry.content {
            case .placeholder:
                PaeoniaPlaceholderDrawing()
            case let .drawing(content):
                // Small widgets can show in StandBy while the phone is locked.
                if redactionReasons.contains(.privacy) {
                    redactedContent
                } else {
                    drawingImageView(content)
                }
            case .redacted:
                redactedContent
            }
        }
        // Dims while a refresh tap is running, so the tap visibly does something.
        .invalidatableContent()
    }

    private func drawingImageView(_ content: PaeoniaWidgetDrawingContent) -> some View {
        Image(uiImage: content.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(DrawingCanvasShape())
            .privacySensitive()
            .accessibilityLabel(drawingAccessibilityLabel(for: content))
    }

    private func drawingAccessibilityLabel(for content: PaeoniaWidgetDrawingContent) -> Text {
        if let authorName = content.authorName, !authorName.isEmpty {
            Text(.widgetDrawingAccessibility(authorName))
        } else {
            Text(.widgetDrawingTitle)
        }
    }

    private var redactedContent: some View {
        VStack(spacing: PaeoniaWidgetSpacing.space8) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: redactedIconSize, weight: .semibold))
                .foregroundStyle(.paeoniaWidgetAccentPrimary)
                .accessibilityHidden(true)

            Text(.widgetRedactedTitle)
                .font(PaeoniaWidgetTypography.title(family: family))
                .foregroundStyle(.paeoniaWidgetTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The title and the time or action stack on the left, so neither has to
    /// shrink to share one line in the small widget.
    private var footer: some View {
        HStack(alignment: .center, spacing: PaeoniaWidgetSpacing.space8) {
            VStack(alignment: .leading, spacing: 2) {
                footerLeadingContent

                footerDetailLabel
                    .font(PaeoniaWidgetTypography.metadata(family: family))
                    .foregroundStyle(footerDetailColor)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            refreshButton
        }
    }

    @ViewBuilder
    private var footerDetailLabel: some View {
        if let savedAt = drawingContent?.savedAt {
            Text(timestampText(savedAt))
                .invalidatableContent()
        } else if family != .systemSmall {
            // The whole widget opens the app, so the small one skips the hint
            // and gives the title its two lines.
            Text(footerAction)
        }
    }

    private var footerDetailColor: Color {
        drawingContent?.savedAt == nil
            ? .paeoniaWidgetAccentPrimary
            : .paeoniaWidgetTextSecondary
    }

    private var footerLeadingContent: some View {
        footerLeadingLabel
            .font(PaeoniaWidgetTypography.title(family: family))
            .foregroundStyle(.paeoniaWidgetTextPrimary)
            // No shrinking: widget text stays at 11 pt or larger.
            .lineLimit(family == .systemSmall ? 2 : 1)
    }

    @ViewBuilder
    private var footerLeadingLabel: some View {
        if let authorName = drawingContent?.authorName, !authorName.isEmpty {
            Text(verbatim: authorName)
                .privacySensitive()
        } else {
            Text(footerTitle)
        }
    }

    private var footerTitle: LocalizedStringResource {
        switch entry.content {
        case .placeholder:
            .widgetPlaceholderTitle
        case .drawing:
            .widgetDrawingTitle
        case .redacted:
            .widgetRedactedSubtitle
        }
    }

    private var footerAction: LocalizedStringResource {
        switch entry.content {
        case .placeholder, .redacted:
            .widgetPlaceholderAction
        case .drawing:
            .widgetDrawingAction
        }
    }

    private var refreshButton: some View {
        Button(intent: PaeoniaWidgetRefreshIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: family == .systemSmall ? 12 : 14, weight: .semibold))
                .frame(width: refreshHitTargetSize, height: refreshHitTargetSize)
        }
        .tint(.paeoniaWidgetAccentPrimary)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(.widgetRefresh))
    }

    private var drawingContent: PaeoniaWidgetDrawingContent? {
        if case let .drawing(content) = entry.content {
            return content
        }
        return nil
    }

    private var refreshHitTargetSize: CGFloat {
        family == .systemSmall ? 36 : 40
    }

    /// Compares against the entry date, not the clock: WidgetKit renders every
    /// entry when the timeline is built, so "today" must mean the entry's day.
    private func timestampText(_ date: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: entry.date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var redactedIconSize: CGFloat {
        family == .systemSmall ? 22 : 28
    }
}

private enum PaeoniaWidgetURL {
    // A fixed, known-valid literal URL; the optional initializer cannot fail here.
    static let drawing = URL(string: "paeonia://widget/drawing")!
}

private struct PaeoniaWidgetDrawingArea<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            content
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

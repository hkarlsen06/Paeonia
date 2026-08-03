import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct PaeoniaWidgetEntryView: View {
    let entry: PaeoniaWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        overlayContent
            .widgetURL(PaeoniaWidgetURL.drawing)
            .accessibilityElement(children: .contain)
    }

    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaWidgetSpacing.space6) {
            header

            middleContent

            footer
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var drawingImage: UIImage? {
        guard case let .drawing(content) = entry.content else {
            return nil
        }
        return UIImage(contentsOfFile: content.previewURL.path)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: PaeoniaWidgetSpacing.space8) {
            HStack(alignment: .center, spacing: PaeoniaWidgetSpacing.space6) {
                Image(.paeoniaMark)
                    .resizable()
                    .scaledToFit()
                    .frame(width: markWidth, height: markHeight)
                    .accessibilityHidden(true)

                Text(.widgetTitle)
                    .font(PaeoniaWidgetTypography.wordmark(family: family))
                    .foregroundStyle(.paeoniaWidgetTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .layoutPriority(1)

            Spacer(minLength: PaeoniaWidgetSpacing.space8)

            refreshButton
        }
    }

    /// The square PencilKit raster sits centered on the plum widget background,
    /// with the header above and metadata below it, so artwork never reads as a
    /// full-bleed background and metadata never floats over a stroke.
    @ViewBuilder
    private var middleContent: some View {
        PaeoniaWidgetDrawingArea {
            switch entry.content {
            case .placeholder:
                PaeoniaPlaceholderDrawing()
            case .drawing:
                if let drawingImage {
                    Image(uiImage: drawingImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .accessibilityHidden(true)
                } else {
                    PaeoniaPlaceholderDrawing()
                }
            case .redacted:
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
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaeoniaWidgetSpacing.space8) {
            footerLeadingContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            footerTrailingLabel
                .font(PaeoniaWidgetTypography.metadata(family: family))
                .foregroundStyle(footerTrailingColor)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }

    @ViewBuilder
    private var footerTrailingLabel: some View {
        if let savedAt = drawingContent?.savedAt {
            Text(Self.timestampText(savedAt))
        } else {
            Text(footerAction)
        }
    }

    private var footerTrailingColor: Color {
        drawingContent?.savedAt == nil
            ? .paeoniaWidgetAccentPrimary
            : .paeoniaWidgetTextSecondary
    }

    private var footerLeadingContent: some View {
        footerLeadingLabel
            .font(PaeoniaWidgetTypography.title(family: family))
            .foregroundStyle(.paeoniaWidgetTextPrimary)
            .lineLimit(family == .systemSmall ? 2 : 1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var footerLeadingLabel: some View {
        if let authorName = drawingContent?.authorName, !authorName.isEmpty {
            Text(verbatim: authorName)
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

    private static func timestampText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var contentPadding: CGFloat {
        family == .systemSmall ? PaeoniaWidgetSpacing.space10 : PaeoniaWidgetSpacing.space12
    }

    private var markWidth: CGFloat {
        family == .systemSmall ? 24 : 28
    }

    private var markHeight: CGFloat {
        family == .systemSmall ? 13 : 15
    }

    private var redactedIconSize: CGFloat {
        family == .systemSmall ? 22 : 28
    }
}

private enum PaeoniaWidgetURL {
    // A fixed, known-valid literal URL; the optional initializer cannot fail here.
    // swiftlint:disable:next force_unwrapping
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

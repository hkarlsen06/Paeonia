import SwiftUI
import UIKit
import WidgetKit

struct PaeoniaWidgetEntryView: View {
    let entry: PaeoniaWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack(alignment: .topLeading) {
            overlayContent
            refreshButtonLayer
        }
        .widgetURL(PaeoniaWidgetURL.drawing)
        // `.contain` (not `.combine`) so the interactive refresh button stays a
        // separately actionable accessibility element.
        .accessibilityElement(children: .contain)
    }

    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            header

            middleContent

            footer
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
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

            headerTrailing
        }
    }

    @ViewBuilder
    private var headerTrailing: some View {
        headerTrailingLabel
            .font(PaeoniaWidgetTypography.metadata(family: family))
            .foregroundStyle(.paeoniaWidgetTextSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    @ViewBuilder
    private var headerTrailingLabel: some View {
        if let savedAt = drawingContent?.savedAt {
            Text(Self.timestampText(savedAt))
        } else {
            Text(.widgetPlaceholderSubtitle)
        }
    }

    /// A contained square preserves the exact canvas coordinate space instead
    /// of cropping a drawing behind widget chrome. The surrounding breathing
    /// room keeps the widget identity and attribution legible without covering
    /// any strokes.
    @ViewBuilder
    private var middleContent: some View {
        PaeoniaWidgetDrawingArea(cornerRadius: canvasCornerRadius) {
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

    private var footer: some View {
        HStack(alignment: .center, spacing: PaeoniaWidgetSpacing.space8) {
            footerLeadingLabel
                .font(PaeoniaWidgetTypography.title(family: family))
                .foregroundStyle(.paeoniaWidgetTextPrimary)
                .lineLimit(family == .systemSmall ? 2 : 1)
                .minimumScaleFactor(0.7)
                .allowsHitTesting(false)
                .layoutPriority(1)

            Spacer(minLength: PaeoniaWidgetSpacing.space8)

            footerTrailing
        }
    }

    @ViewBuilder
    private var footerLeadingLabel: some View {
        if let authorName = drawingContent?.authorName, !authorName.isEmpty {
            Text(verbatim: authorName)
        } else {
            Text(footerTitle)
        }
    }

    @ViewBuilder
    private var footerTrailing: some View {
        if case .drawing = entry.content {
            Color.clear
                .frame(width: refreshButtonSize, height: refreshButtonSize)
                .accessibilityHidden(true)
        } else {
            Text(footerAction)
                .font(PaeoniaWidgetTypography.action(family: family))
                .foregroundStyle(.paeoniaWidgetAccentPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsHitTesting(false)
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

    @ViewBuilder
    private var refreshButtonLayer: some View {
        if case .drawing = entry.content {
            VStack {
                Spacer(minLength: 0)

                HStack {
                    Spacer(minLength: 0)

                    refreshButton
                }
            }
            .padding(contentPadding)
        }
    }

    private var refreshButton: some View {
        // The extension cannot authenticate to the couple's Supabase session.
        // Opening this dedicated route lets the host app perform a real sync;
        // a local-only `reloadTimelines` would simply repaint stale bytes.
        Link(destination: PaeoniaWidgetURL.refresh) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold))
                .foregroundStyle(.paeoniaWidgetAccentPrimary)
                .frame(width: refreshButtonSize, height: refreshButtonSize)
                .background(.paeoniaWidgetAccentPrimary.opacity(0.16), in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(Text(.widgetRefresh))
    }

    private var drawingContent: PaeoniaWidgetDrawingContent? {
        if case let .drawing(content) = entry.content {
            return content
        }
        return nil
    }

    private var refreshButtonSize: CGFloat {
        family == .systemSmall ? 36 : 42
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

    private var contentSpacing: CGFloat {
        family == .systemSmall ? PaeoniaWidgetSpacing.space8 : PaeoniaWidgetSpacing.space12
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

    private var canvasCornerRadius: CGFloat {
        family == .systemSmall ? PaeoniaWidgetRadius.canvasSmall : PaeoniaWidgetRadius.canvasLarge
    }
}

private enum PaeoniaWidgetURL {
    // A fixed, known-valid literal URL; the optional initializer cannot fail here.
    // swiftlint:disable:next force_unwrapping
    static let drawing = URL(string: "paeonia://widget/drawing")!
    // swiftlint:disable:next force_unwrapping
    static let refresh = URL(string: "paeonia://widget/refresh")!
}

private struct PaeoniaWidgetDrawingArea<Content: View>: View {
    let cornerRadius: CGFloat
    private let content: Content

    init(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            content
                .frame(width: side, height: side)
                .background(.paeoniaWidgetCanvasSurface)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.paeoniaWidgetCanvasBorder, lineWidth: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

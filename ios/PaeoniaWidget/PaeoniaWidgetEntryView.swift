import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct PaeoniaWidgetEntryView: View {
    let entry: PaeoniaWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack(alignment: .topLeading) {
            openDrawingBackgroundLink
            overlayContent
            refreshButtonLayer
        }
        // `.contain` (not `.combine`) so the interactive refresh button stays a
        // separately actionable accessibility element.
        .accessibilityElement(children: .contain)
    }

    private var openDrawingBackgroundLink: some View {
        Link(destination: PaeoniaWidgetURL.drawing) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(Text(footerAction))
    }

    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            header

            middleContent

            footer
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The saved drawing fills the whole widget edge to edge, so a partner
        // filling the canvas colors the entire widget instead of a small square
        // in the middle.
        .background {
            drawingBackground
        }
        .allowsHitTesting(false)
    }

    /// The saved drawing rendered full-bleed behind the header and footer. Only
    /// real drawings fill the widget; the placeholder and redacted states stay in
    /// the centered band via `middleContent`.
    @ViewBuilder
    private var drawingBackground: some View {
        if let image = drawingImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityHidden(true)
        }
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

    /// The content shown in the middle band between header and footer. A real
    /// drawing is rendered full-bleed behind everything (see `drawingBackground`),
    /// so here it only takes up flexible space; the placeholder and redacted
    /// states stay centered in the band.
    @ViewBuilder
    private var middleContent: some View {
        switch entry.content {
        case .placeholder:
            PaeoniaWidgetDrawingArea {
                PaeoniaPlaceholderDrawing()
            }
        case .drawing:
            if drawingImage == nil {
                PaeoniaWidgetDrawingArea {
                    PaeoniaPlaceholderDrawing()
                }
            } else {
                Spacer(minLength: 0)
            }
        case .redacted:
            PaeoniaWidgetDrawingArea {
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
        Button(intent: PaeoniaWidgetRefreshIntent()) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold))
                .foregroundStyle(.paeoniaWidgetAccentPrimary)
                .frame(width: refreshButtonSize, height: refreshButtonSize)
                .background(.paeoniaWidgetAccentPrimary.opacity(0.16), in: Circle())
                .contentShape(Circle())
                // Shows the system "working" treatment while the refresh
                // intent runs, so the tap has visible feedback.
                .invalidatableContent()
        }
        .buttonStyle(.plain)
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
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

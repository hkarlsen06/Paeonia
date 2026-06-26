import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct PaeoniaWidgetEntryView: View {
    let entry: PaeoniaWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack(alignment: .topLeading) {
            openDrawingBackgroundButton

            VStack(alignment: .leading, spacing: contentSpacing) {
                header
                    .allowsHitTesting(false)

                drawingSurface
                    .allowsHitTesting(false)

                footer
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // `.contain` (not `.combine`) so the interactive refresh button stays a
        // separately actionable accessibility element.
        .accessibilityElement(children: .contain)
    }

    private var openDrawingBackgroundButton: some View {
        Button(intent: PaeoniaWidgetOpenDrawingIntent()) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(footerAction))
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

    @ViewBuilder
    private var drawingSurface: some View {
        switch entry.content {
        case .placeholder:
            PaeoniaWidgetDrawingArea {
                PaeoniaPlaceholderDrawing()
            }
        case let .drawing(content):
            PaeoniaWidgetDrawingArea {
                if let image = UIImage(contentsOfFile: content.previewURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(PaeoniaWidgetSpacing.space6)
                        .accessibilityHidden(true)
                } else {
                    PaeoniaPlaceholderDrawing()
                }
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
            Button(intent: PaeoniaWidgetRefreshIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: family == .systemSmall ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.paeoniaWidgetAccentPrimary)
                    .frame(width: refreshButtonSize, height: refreshButtonSize)
                    .background(.paeoniaWidgetAccentPrimary.opacity(0.16), in: Circle())
                    // Shows the system "working" treatment while the refresh
                    // intent runs, so the tap has visible feedback.
                    .invalidatableContent()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(.widgetRefresh))
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

    private var drawingContent: PaeoniaWidgetDrawingContent? {
        if case let .drawing(content) = entry.content {
            return content
        }
        return nil
    }

    private var refreshButtonSize: CGFloat {
        family == .systemSmall ? 26 : 30
    }

    private static func timestampText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var contentPadding: CGFloat {
        family == .systemSmall ? PaeoniaWidgetSpacing.space14 : PaeoniaWidgetSpacing.space16
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

import PencilKit
import SwiftUI

/// The row above the canvas: what the widgets show right now (who drew it, and
/// when) and whether the canvas holds something not sent yet. Always one line
/// tall, also while the first drawing loads, so the square canvas never jumps.
struct WidgetDrawingCanvasHeader: View {
    let viewModel: WidgetDrawingViewModel
    let partnerName: String

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            headerLeading
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: PaeoniaSpacing.space8)

            headerTrailing
        }
        .frame(minHeight: PaeoniaSpacing.space24)
        .padding(.horizontal, PaeoniaSpacing.space8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    @ViewBuilder
    private var headerLeading: some View {
        if viewModel.partnerSentWhileEditing {
            Label {
                Text(.widgetDrawingPartnerSentShort(partnerName))
            } icon: {
                Image(systemName: "sparkles")
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
        } else {
            Text(verbatim: viewModel.isShowingSavedAttribution ? (viewModel.savedDrawingAuthorName ?? " ") : " ")
                .font(PaeoniaTypography.widgetPrimary)
                .foregroundStyle(.paeoniaTextPrimary)
        }
    }

    @ViewBuilder
    private var headerTrailing: some View {
        if isNotSentYet {
            Text(.widgetDrawingNotSent)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(1)
                .padding(.horizontal, PaeoniaSpacing.space8)
                .padding(.vertical, PaeoniaSpacing.space4)
                .background(.paeoniaSurfacePrimary, in: Capsule(style: .continuous))
        } else if viewModel.isShowingSavedAttribution, let createdAt = viewModel.savedDrawingCreatedAt {
            Text(verbatim: Self.attributionTimestamp(createdAt))
                .font(PaeoniaTypography.widgetSecondary)
                .foregroundStyle(.paeoniaTextSecondary)
                .lineLimit(1)
        }
    }

    /// The canvas has strokes that differ from the widgets, or the last send has
    /// not reached the partner. An empty canvas cannot be sent, so it is not
    /// "not sent".
    private var isNotSentYet: Bool {
        (viewModel.hasUnsavedEdits && !viewModel.drawing.strokes.isEmpty && !viewModel.isPublishing)
            || viewModel.delivery == .waiting
    }

    private var headerAccessibilityLabel: Text {
        var parts: [String] = []
        if viewModel.partnerSentWhileEditing {
            parts.append(String(localized: .widgetDrawingPartnerSentMessage(partnerName)))
        } else if viewModel.isShowingSavedAttribution,
                  let author = viewModel.savedDrawingAuthorName,
                  let createdAt = viewModel.savedDrawingCreatedAt {
            parts.append(String(localized: .widgetDrawingOnWidgetAccessibility(
                author,
                Self.attributionTimestamp(createdAt)
            )))
        }
        if viewModel.delivery == .waiting {
            parts.append(String(localized: .widgetDrawingWaitingMessage(partnerName)))
        } else if isNotSentYet {
            parts.append(String(localized: .widgetDrawingNotSent))
        }
        // A line break makes VoiceOver pause between the parts.
        return Text(verbatim: parts.joined(separator: "\n"))
    }

    /// Matches the widget's timestamp treatment: just the time today, otherwise
    /// the date.
    nonisolated private static func attributionTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

import PencilKit
import SwiftUI

/// The row above the canvas: what the widgets show right now (who drew it, and
/// when) and whether the canvas holds something not sent yet. At accessibility
/// text sizes, the status follows the attribution in a separate row.
struct WidgetDrawingCanvasHeader: View {
    let viewModel: WidgetDrawingViewModel
    let partnerName: String
    /// Whether the "Not sent yet" pill can show. Off before an account exists, when
    /// there is no one to send to yet.
    var showsSendStatus = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        headerLayout {
            headerLeading
                .layoutPriority(1)

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: PaeoniaSpacing.space8) }

            headerTrailing
        }
        .frame(minHeight: PaeoniaSpacing.space24)
        .padding(.horizontal, PaeoniaSpacing.space8)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!viewModel.partnerSentWhileEditing && livePresenceText == nil
            && !viewModel.isShowingSavedAttribution && !(showsSendStatus && isNotSentYet))
    }

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space8))
            : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space8))
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
        } else if let presence = livePresenceText {
            Label {
                Text(verbatim: presence)
            } icon: {
                Image(systemName: viewModel.live?.partnerActivity == .drawing ? "hand.draw" : "eye")
            }
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
        } else {
            HStack(spacing: PaeoniaSpacing.space8) {
                Text(verbatim: viewModel.isShowingSavedAttribution ? (viewModel.savedDrawingAuthorName ?? " ") : " ")
                    .font(PaeoniaTypography.caption.weight(.semibold))
                    .accessibilityLabel(attributionLabel)
                    .accessibilityHidden(!viewModel.isShowingSavedAttribution)
                    .foregroundStyle(.paeoniaTextPrimary)
                if viewModel.isShowingSavedAttribution {
                    // What the partner reacted with, or what the user did to the partner's drawing.
                    WidgetDrawingReactionControl(
                        shownRevisionID: WidgetCanvasSyncService.lastSyncedRevisionID(),
                        part: .badge
                    )
                }
            }
        }
    }

    /// The pill is always laid out, only hidden, so the row keeps its height.
    /// On iPad the canvas fills the height that is left, and a row that grows
    /// and shrinks would resize the canvas each time the status changes.
    private var headerTrailing: some View {
        ZStack(alignment: .trailing) {
            Text(.widgetDrawingNotSent)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .padding(.horizontal, PaeoniaSpacing.space8)
                .padding(.vertical, PaeoniaSpacing.space4)
                .background(.paeoniaSurfacePrimary, in: Capsule(style: .continuous))
                .opacity(showsSendStatus && isNotSentYet ? 1 : 0)
                .accessibilityHidden(!showsSendStatus || !isNotSentYet)

            if !isNotSentYet, viewModel.isShowingSavedAttribution, let createdAt = viewModel.savedDrawingCreatedAt {
                Text(verbatim: Self.attributionTimestamp(createdAt))
                    .font(PaeoniaTypography.caption)
                    .accessibilityHidden(true)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
    }

    /// Whether the partner draws along or watches from their Us tab.
    private var livePresenceText: String? {
        switch viewModel.live?.partnerActivity {
        case .drawing:
            String(localized: .widgetDrawingLiveTogether(partnerName))
        case .watching:
            String(localized: .widgetDrawingLiveWatching(partnerName))
        case .away, .choosing, .result, .present, nil:
            // The widget canvas never meets the game-only roles.
            nil
        }
    }

    /// The canvas has strokes that the person has not chosen to send yet.
    /// An empty canvas cannot be sent.
    private var isNotSentYet: Bool {
        viewModel.hasUnsavedEdits && !viewModel.drawing.strokes.isEmpty && !viewModel.isPublishing
    }

    private var attributionLabel: Text {
        guard let author = viewModel.savedDrawingAuthorName,
              let createdAt = viewModel.savedDrawingCreatedAt else {
            return Text(verbatim: viewModel.savedDrawingAuthorName ?? "")
        }
        return Text(.widgetDrawingOnWidgetAccessibility(author, Self.attributionTimestamp(createdAt)))
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

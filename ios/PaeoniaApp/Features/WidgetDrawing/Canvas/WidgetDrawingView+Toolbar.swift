import SwiftUI

/// The buttons in the drawing screen's navigation bar.
extension WidgetDrawingView {
    /// The reaction target of the partner's drawing, when it is the one on screen.
    var partnersDrawingReaction: WidgetDrawingReactionTarget? {
        guard viewModel.isShowingSavedAttribution,
              let reaction = LatestWidgetDrawing.shared.reactionTarget(
                  showing: WidgetCanvasSyncService.lastSyncedRevisionID(),
                  currentUserID: reactionStore?.participants.currentUserID
              ),
              reaction.isFromPartner
        else {
            return nil
        }
        return reaction
    }

    @ToolbarContentBuilder
    var toolbarButtons: some ToolbarContent {
        // Only the partner's drawing takes a reaction. A button without one would show as an empty pill.
        if reactionStore != nil, let reaction = partnersDrawingReaction {
            ToolbarItem(placement: .topBarTrailing) {
                ReactionPickerButton(target: reaction.target, style: .toolbar)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.revertToSavedDrawing()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!viewModel.canRevertToSavedDrawing)
            .accessibilityLabel(Text(.widgetDrawingRevertButton))
        }
        if showsHistory {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isHistoryPresented = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text(.widgetHistoryOpenButton))
            }
        }
    }
}

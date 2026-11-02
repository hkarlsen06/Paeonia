import SwiftUI

/// Where a tap on the Home look-back card goes.
extension MainTabView {
    func openLookBack(_ item: LookBackItem) {
        switch item.destination {
        case let .questionChat(instanceID):
            startOpeningDailyChat(instanceID: instanceID)
        case let .drawingHistory(revisionID):
            lookBackDrawingRevisionID = revisionID
            isLookBackDrawingHistoryPresented = true
        case let .memory(id):
            selection.wrappedValue = .memories
            memoriesPath = [id]
        case nil:
            break
        }
    }
}

extension View {
    /// The drawing history as a sheet over Home, the same screen the drawing screen opens.
    func lookBackDrawingHistory(
        isPresented: Binding<Bool>, revisionID: UUID?, dependencies: RootFeatureDependencies
    ) -> some View {
        sheet(isPresented: isPresented) {
            if let viewModel = dependencies.widgetHistoryViewModel,
               let thumbnailLoader = dependencies.widgetHistoryThumbnailLoader {
                WidgetDrawingHistoryView(
                    viewModel: viewModel, thumbnailLoader: thumbnailLoader, initialRevisionID: revisionID
                )
                    .analyticsScreen("drawing_history")
            } else {
                WidgetDrawingHistoryView(initialRevisionID: revisionID)
                    .analyticsScreen("drawing_history")
            }
        }
    }
}

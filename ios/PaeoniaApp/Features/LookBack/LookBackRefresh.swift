import SwiftUI

/// Keeps the look-back item current from Home. Every read runs in a task tied to the view, so
/// leaving Home or the app tearing the tabs down cancels it and drops its answer. The modifier sits on
/// the Home scroll view and not on the card, because the card does not exist while there is nothing
/// to show.
private struct LookBackRefreshModifier: ViewModifier {
    let viewModel: LookBackViewModel?
    let userID: UUID?
    let coupleID: UUID?

    @Environment(\.scenePhase) private var scenePhase
    @State private var dayChanges = 0

    /// Anything that calls for a new read. The couple id is not part of it: it arrives after launch
    /// and would cancel a read in flight.
    private struct Trigger: Equatable {
        let userID: UUID?
        let isActive: Bool
        let dayChanges: Int
        let refreshRequest: Int
    }

    func body(content: Content) -> some View {
        content
            // Runs when Home appears, when the app returns to the foreground, when the calendar day
            // changes, and when the couple becomes known.
            .task(id: Trigger(
                userID: userID,
                isActive: scenePhase == .active,
                dayChanges: dayChanges,
                refreshRequest: viewModel?.refreshRequest ?? 0
            )) {
                guard scenePhase == .active else { return }
                await viewModel?.configure(userID: userID, coupleID: coupleID)
            }
            .task(id: userID) {
                await viewModel?.observeStoreChanges()
            }
            // Reads again when the couple's day ends, because the server picks a new item then.
            .task(id: viewModel?.refreshAt) {
                guard let endsAt = viewModel?.refreshAt else { return }
                let wait = endsAt.timeIntervalSinceNow
                // A day end already in the past would loop, so wait a quarter of an hour instead.
                try? await Task.sleep(for: .seconds(wait > 0 ? wait + 1 : 900))
                guard !Task.isCancelled else { return }
                await viewModel?.refresh()
            }
            .onChange(of: coupleID) { _, coupleID in
                viewModel?.updateCouple(coupleID)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                dayChanges += 1
            }
    }
}

extension View {
    func lookBackRefresh(_ viewModel: LookBackViewModel?, userID: UUID?, coupleID: UUID?) -> some View {
        modifier(LookBackRefreshModifier(viewModel: viewModel, userID: userID, coupleID: coupleID))
    }
}

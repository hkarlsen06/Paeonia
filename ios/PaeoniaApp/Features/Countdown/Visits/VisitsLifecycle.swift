import SwiftUI

extension View {
    /// Puts `visits` in the environment for the Us tab card, the visit screen and the dates
    /// timeline, loads this person's visits, follows the live feed, and shows a failed write
    /// as a banner.
    func visitsLifecycle(
        _ visits: VisitsViewModel,
        ownerUserID: UUID?,
        sync: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(VisitsLifecycle(visits: visits, ownerUserID: ownerUserID, syncAfterLocalChange: sync))
    }
}

private struct VisitsLifecycle: ViewModifier {
    let visits: VisitsViewModel
    let ownerUserID: UUID?
    let syncAfterLocalChange: @MainActor () async -> Void

    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    func body(content: Content) -> some View {
        content
            .environment(visits)
            .task(id: ownerUserID) {
                visits.setSyncAfterLocalChange(syncAfterLocalChange)
                await visits.configure(ownerUserID: ownerUserID)
                await visits.observeStoreChanges()
            }
            .onChange(of: visits.error) { _, error in
                guard let error else { return }
                bannerCenter.show(.error(message: error.message))
                visits.clearError()
            }
    }
}

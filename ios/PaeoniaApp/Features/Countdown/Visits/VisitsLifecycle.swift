import SwiftUI

extension View {
    /// Puts `visits` in the environment for the Us tab card, the visit screen and the dates
    /// timeline, loads this person's visits, follows the live feed, and shows a failed write
    /// as a banner while the app is on screen.
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
    @Environment(\.scenePhase) private var scenePhase
    /// The banner on screen that names refused writes.
    @State private var refusalBannerID: UUID?

    func body(content: Content) -> some View {
        content
            .environment(visits)
            .task(id: ownerUserID) {
                visits.setSyncAfterLocalChange(syncAfterLocalChange)
                await visits.configure(ownerUserID: ownerUserID)
                await visits.observeStoreChanges()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                Task { await visits.setActive(phase == .active) }
            }
            .onChange(of: visits.error) { _, error in
                guard let error else { return }
                bannerCenter.show(.error(message: error.message))
                if error.namesRefusals { refusalBannerID = bannerCenter.content?.id }
                visits.clearError()
            }
            // An error banner stays until the person dismisses it or another banner takes its place.
            .onChange(of: bannerCenter.content?.id) { _, shown in
                guard let refusalBannerID, shown != refusalBannerID else { return }
                self.refusalBannerID = nil
                if shown == nil {
                    Task { await visits.refusalBannerDismissed() }
                } else {
                    visits.refusalBannerReplaced()
                }
            }
    }
}

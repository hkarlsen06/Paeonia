import SwiftUI

extension View {
    /// Tells the hearts model when Home is on screen, so the partner's hearts play
    /// only where the person can see them.
    func heartsLifecycle(_ hearts: HeartsViewModel?, ownerUserID: UUID?, partnerName: String) -> some View {
        modifier(HeartsHomeLifecycle(hearts: hearts, ownerUserID: ownerUserID, partnerName: partnerName))
    }
}

private struct HeartsHomeLifecycle: ViewModifier {
    let hearts: HeartsViewModel?
    let ownerUserID: UUID?
    let partnerName: String

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.launchIntroComplete) private var launchIntroComplete

    /// The app is in front and the launch intro is over.
    private var isScreenReady: Bool {
        scenePhase == .active && launchIntroComplete
    }

    func body(content: Content) -> some View {
        content
            .onAppear { hearts?.setHomeVisible(true) }
            .onDisappear { hearts?.setHomeVisible(false) }
            .onChange(of: isScreenReady, initial: true) { _, isReady in
                hearts?.setScreenReady(isReady)
            }
            // The partner's name arrives after launch and never restarts the task.
            .onChange(of: partnerName, initial: true) {
                hearts?.configure(ownerUserID: ownerUserID, partnerName: partnerName)
            }
            .task(id: ownerUserID) {
                hearts?.configure(ownerUserID: ownerUserID, partnerName: partnerName)
                await hearts?.observeStoreChanges()
            }
    }
}

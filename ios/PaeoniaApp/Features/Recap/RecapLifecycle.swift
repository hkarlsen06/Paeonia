import SwiftUI

extension View {
    func recapLifecycle(
        _ recap: RecapViewModel, userID: UUID?, coupleID: UUID?, startedOn: String?, people: RecapPeople
    ) -> some View {
        modifier(RecapLifecycle(recap: recap, userID: userID, coupleID: coupleID, startedOn: startedOn, people: people))
    }
}

private struct RecapLifecycle: ViewModifier {
    @Bindable var recap: RecapViewModel
    let userID: UUID?
    let coupleID: UUID?
    let startedOn: String?
    let people: RecapPeople

    @Environment(\.scenePhase) private var scenePhase
    @State private var dayChanges = 0

    private struct Trigger: Equatable {
        let userID: UUID?
        let coupleID: UUID?
        let startedOn: String?
        let isActive: Bool
        let dayChanges: Int
    }

    func body(content: Content) -> some View {
        content
            .environment(recap)
            .task(id: Trigger(
                userID: userID, coupleID: coupleID, startedOn: startedOn,
                isActive: scenePhase == .active, dayChanges: dayChanges
            )) {
                guard scenePhase == .active else { return }
                await recap.configure(userID: userID, coupleID: coupleID, startedOn: startedOn)
            }
            .onChange(of: people, initial: true) { _, people in
                recap.people = people
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                dayChanges += 1
            }
            .sheet(item: $recap.presented) { shown in
                RecapView(model: recap, recap: shown)
                    .analyticsScreen("recap")
            }
    }
}

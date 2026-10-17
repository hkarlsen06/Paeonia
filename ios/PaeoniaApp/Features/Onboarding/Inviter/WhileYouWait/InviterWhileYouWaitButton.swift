import SwiftUI

/// The invite screen's way into "While you wait": one card that says how many of the two
/// things are made and opens them in a sheet. It also loads the first day draft, since
/// it stays on screen while the code is out.
struct InviterWhileYouWaitButton: View {
    let model: InviterFirstDayModel

    @State private var isOpen = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @Environment(\.scenePhase) private var scenePhase

    private var doneCount: Int {
        (model.hasAnsweredQuestions ? 1 : 0) + (model.hasDrawing ? 1 : 0)
    }

    private var isAllDone: Bool {
        doneCount == 2
    }

    var body: some View {
        InviterFirstDayRow(
            title: .inviterWhileYouWaitTitle,
            subtitle: isAllDone ? .inviterWhileYouWaitButtonDone : .inviterWhileYouWaitButtonSubtitle,
            isDone: isAllDone,
            completion: nil,
            action: { isOpen = true }
        ) {
            InviterFirstDayRowIcon(systemImage: "gift.fill")
        } trailing: {
            InviterQuestionsProgress(
                answered: doneCount,
                total: 2,
                label: { .inviterWhileYouWaitProgress($0, $1) }
            )
        }
        .screenEntrance(order: 1, isReady: model.hasLoaded)
        .task {
            await model.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshOnForeground() }
            }
        }
        .onChange(of: model.loadFailure) { _, failure in
            guard let failure else {
                return
            }
            bannerCenter.show(.error(
                title: String(localized: .inviterQuestionsLoadFailedTitle),
                message: String(
                    localized: failure == .offline
                        ? .inviterQuestionsLoadFailedOfflineMessage
                        : .commonActionFailedMessage
                )
            ))
            model.clearLoadFailure()
        }
        .sheet(isPresented: $isOpen) {
            InviterWhileYouWaitSheet(model: model)
                .environment(bannerCenter)
        }
    }
}

import SwiftUI

extension MainTabView {
    func withRecap(_ home: some View) -> some View {
        home.recapLifecycle(
            models.recap,
            userID: identity.currentUserID,
            coupleID: identity.coupleID,
            startedOn: milestoneViewModel.startedOn,
            people: RecapPeople(
                currentUserID: identity.currentUserID,
                currentName: identity.currentDisplayName ?? "",
                partnerName: dailyChallengeParticipants.partnerName,
                partnerSharedName: identity.partnerName?.sharedName ?? ""
            )
        )
    }

    func presentUsSheet(for deepLink: PaeoniaDeepLink, isCurrent: () -> Bool) async -> Bool {
        switch deepLink {
        case let .mail(letterID):
            await mailViewModel.presentLink(letterID, isCurrent: isCurrent)
        case let .recap(anniversaryDate):
            await models.recap.presentLink(
                anniversaryDate, startedOn: milestoneViewModel.startedOn, isCurrent: isCurrent
            )
        default:
            true
        }
    }
}

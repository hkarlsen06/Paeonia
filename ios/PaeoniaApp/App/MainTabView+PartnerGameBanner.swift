import SwiftUI

/// The banner on other tabs that says the partner opened a game and invites this person in.
extension MainTabView {
    /// The partner just opened `kind`. Home and the Games hub already show who is in
    /// which game, and a person already in that game, or in the middle of answering,
    /// gets no banner.
    func announcePartnerGame(_ kind: GameKind?) {
        guard let kind, selection.wrappedValue != .us,
              !(selection.wrappedValue == .games && (gamesPath.isEmpty || gamesPath.contains(.game(kind)))),
              !isAnswerFlowPresented, partnerAnswerQuestion == nil
        else { return }

        let gameName = String(localized: kind.name)
        bannerCenter.show(
            .info(
                title: String(localized: .gamesPartnerOpenedTitle(gamesViewModel.partnerName, gameName)),
                message: String(localized: .gamesPartnerOpenedMessage),
                gameKind: kind,
                imageData: PaeoniaAppGroup.partnerAvatarData(),
                systemImage: "gamecontroller.fill",
                action: { openGameFromHome(.game(kind)) }
            )
        )
        // The center keeps a banner that reads the same, with its own id.
        partnerGameBanner = bannerCenter.content
    }

    /// The banner stays until dismissed, because it has an action. It is no longer
    /// true once the partner leaves the game or this person opens it.
    var partnerGameBannerIsStale: Bool {
        guard let kind = partnerGameBanner?.gameKind else { return false }
        return !gamesViewModel.partnerGameKinds.contains(kind)
            || selection.wrappedValue == .games && gamesPath.contains(.game(kind))
    }

    func dismissPartnerGameBanner() {
        guard let banner = partnerGameBanner else { return }
        bannerCenter.dismiss(id: banner.id)
        partnerGameBanner = nil
    }
}

#if DEBUG
  import SwiftUI

  /// The in-app banner over a game screen, as it shows when the partner writes
  /// or opens a game while the app is open.
  nonisolated extension DeveloperScenario {
    static let banners: [DeveloperScenario] = [bannerPartnerMessage, bannerPartnerGame]

    static let bannerPartnerMessage = DeveloperScenario(
      "banner-partner-message", "Banner · partner's long message",
      "A long chat message from Robin over the drawing screen", .deepLinks
    ) { _ in DeveloperBannerScenarioView(banner: .partnerMessage) }

    static let bannerPartnerGame = DeveloperScenario(
      "banner-partner-game", "Banner · partner opened a game",
      "Robin opened Draw & Guess while you are drawing", .deepLinks
    ) { _ in DeveloperBannerScenarioView(banner: .partnerOpenedGame) }
  }

  @MainActor
  private struct DeveloperBannerScenarioView: View {
    enum Banner {
      case partnerMessage
      case partnerOpenedGame
    }

    let banner: Banner
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    var body: some View {
      DeveloperGamesScenarioView(scenario: .drawDrawing)
        .paeoniaBanner(bannerCenter)
        .task {
          // The banner arrives over a screen that has appeared, as a live message does.
          try? await Task.sleep(for: .milliseconds(600))
          guard !Task.isCancelled else { return }
          bannerCenter.show(content)
        }
    }

    private var content: PaeoniaBannerContent {
      let partner = DeveloperGamesFixture.participants.partnerName
      let game = String(localized: GameKind.drawAndGuess.name)
      return switch banner {
      case .partnerMessage:
        .info(
          title: String(localized: .gamesChatMessageTitle(partner, game)),
          message: "Haha okay that is definitely a basket, but I keep thinking it looks like the bag you "
            + "forgot at the café last summer. Do you remember? We had to run back in the rain and the "
            + "waiter had already put it behind the counter. Anyway, I'm guessing now!",
          gameKind: .drawAndGuess,
          systemImage: "bubble.left.and.bubble.right.fill",
          action: {}
        )
      case .partnerOpenedGame:
        .info(
          title: String(localized: .gamesPartnerOpenedTitle(partner, game)),
          message: String(localized: .gamesPartnerOpenedMessage),
          gameKind: .drawAndGuess,
          systemImage: "gamecontroller.fill",
          action: {}
        )
      }
    }
  }
#endif

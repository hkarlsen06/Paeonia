#if DEBUG
  import SwiftUI

  /// The in-app banner over a game screen, as it shows when the partner writes while the app is
  /// open and their avatar is not on screen.
  nonisolated extension DeveloperScenario {
    static let banners: [DeveloperScenario] = [bannerPartnerMessage]

    static let bannerPartnerMessage = DeveloperScenario(
      "banner-partner-message", "Banner · partner's long message",
      "A long chat message from Robin over the drawing screen", .deepLinks
    ) { _ in DeveloperBannerScenarioView() }
  }

  @MainActor
  private struct DeveloperBannerScenarioView: View {
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
      return .info(
        title: String(localized: .gamesChatMessageTitle(partner, game)),
        message: "Haha okay that is definitely a basket, but I keep thinking it looks like the bag you "
          + "forgot at the café last summer. Do you remember? We had to run back in the rain and the "
          + "waiter had already put it behind the counter. Anyway, I'm guessing now!",
        gameKind: .drawAndGuess,
        systemImage: "bubble.left.and.bubble.right.fill",
        action: {}
      )
    }
  }
#endif

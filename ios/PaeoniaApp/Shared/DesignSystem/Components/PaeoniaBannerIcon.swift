import SwiftUI

/// Reuses the game's hub objects without a backdrop or a live board preview.
struct PaeoniaBannerGameIcon: View {
    let kind: GameKind

    var body: some View {
        Image(artwork)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private var artwork: ImageResource {
        switch kind {
        case .ludo: .gameHubLudoBoard
        case .drawAndGuess: .gameHubDrawAndGuessPencil
        case .connectFour: .gameHubConnectFourBoard
        case .mindMeld: .gameHubMindMeldCards
        case .consensio: .gameHubConsensioPin
        case .guessMySpot: .gameHubGuessMySpotMap
        case .dotsAndBoxes: .gameHubDotsAndBoxesBoard
        case .ultimateTicTacToe: .gameHubUltimateTicTacToeBoard
        case .piccante: .gameHubPiccanteBox
        case .storyChain: .gameHubStoryChainNotebook
        case .exquisiteCorpse: .gameHubExquisiteCorpseStrip
        }
    }
}

extension PaeoniaDeepLink {
    var bannerGameKind: GameKind? {
        switch self {
        case .game(let kind), .gameChat(let kind): kind
        default: nil
        }
    }

    var bannerSystemImage: String {
        switch self {
        case .widgetDrawing: "pencil.tip.crop.circle.fill"
        case .dailyReveal, .dailyToday, .firstDayAnswer, .topics: "envelope.open.fill"
        case .dailyChat, .coupleChat: "bubble.left.and.bubble.right.fill"
        case .game, .gameChat: "gamecontroller.fill"
        case .memories, .memory, .memoryPhoto, .newMemory: "photo.on.rectangle"
        case .stories, .story: "camera.fill"
        case .mail: "envelope.fill"
        case .us: "heart.fill"
        case .dates: "calendar"
        case .streak: "flame.fill"
        case .subscription: "arrow.clockwise"
        case .dataExport: "square.and.arrow.down"
        case .search: "magnifyingglass"
        }
    }
}

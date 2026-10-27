import SwiftUI

struct GameConversationDrawing: View {
    let assetID: UUID
    @Environment(\.threadChatContext) private var context
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Color.paeoniaBackgroundPrimary
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .accessibilityLabel(Text(.gamesConversationDrawing))
                } else {
                    GameDrawingPlaceholder(loadFailed: failed, retry: load)
                }
            }
            .clipped()
            .task(id: assetID) { await loadImage() }
    }

    private func load() { Task { await loadImage() } }

    private func loadImage() async {
        failed = false
        image = await context.gameDrawings?.thumbnail(for: assetID)
        failed = image == nil
    }
}

struct GameConversationSpot: View {
    let round: RemoteGuessMySpotRound
    let people: GameConversationPeople
    @State private var camera = GuessMySpotCamera.world

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            MemoryMediaImageView(mediaAssetID: round.photoMediaAssetID, height: 200, allowsViewing: true)
            if let place = round.placeName {
                Text(verbatim: place).font(PaeoniaTypography.sectionTitle)
            }
            if let guess = round.guess, let spot = round.spot {
                GuessMySpotMap(
                    position: $camera,
                    pins: [
                        .init(id: "guess", coordinate: guess, style: people.style(for: round.guesserUserID)),
                        .init(id: "spot", coordinate: spot, style: people.style(for: round.senderUserID)),
                    ],
                    line: .init(
                        from: guess, to: spot,
                        isFar: GuessMySpotRules.verdict(distanceMeters: round.knownDistance ?? 0) == .far),
                    showsSatelliteButton: false,
                    accessibilityValue: .guessMySpotMapPinDropped
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
                .onAppear { camera = GuessMySpotCamera.framing(guess, spot) }
            }
            if let distance = round.knownDistance {
                Text(
                    .gamesConversationDistance(
                        people.name(for: round.guesserUserID), GuessMySpotText.distance(distance))
                )
                .font(PaeoniaTypography.body)
            }
        }
    }
}

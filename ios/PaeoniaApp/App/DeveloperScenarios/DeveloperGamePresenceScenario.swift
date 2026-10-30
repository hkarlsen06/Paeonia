#if DEBUG
import SwiftUI

nonisolated extension DeveloperScenario {
    static let gamePresenceControls = DeveloperScenario(
        "game-presence-controls", "Game presence controls",
        "Toggle presence, writing, locking and text size. Use Settings to change Reduce Motion.", .games
    ) { _ in DeveloperGamePresenceScenario() }
}

/// Interactive checks of the production status components without network state.
private struct DeveloperGamePresenceScenario: View {
    @State private var isHere = false
    @State private var isTyping = false
    @State private var isLocked = false
    @State private var largerText = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space24) {
                    Toggle("Partner here", isOn: $isHere)
                    Toggle("Writing signal", isOn: $isTyping)
                    Toggle("Word locked", isOn: $isLocked)
                    Toggle("Larger text", isOn: $largerText)
                    GamePresenceLabel(
                        player: GamePlayer(name: "Robin", photoAssetID: nil),
                        text: isHere ? .gamesPresenceHere : .gamesPresenceAway,
                        isHere: isHere
                    )
                    MindMeldPartnerStatusRow(
                        partner: MindMeldPlayer(name: "Robin", photoAssetID: nil),
                        status: isLocked ? .locked : isHere ? isTyping ? .typing : .here : .away,
                        isPresent: isHere
                    )
                    StoryChainPartnerLine(
                        participants: DeveloperGamesFixture.participants,
                        text: isHere && isTyping ? .storyChainWaitWriting("Robin") : .storyChainWaitGeneric("Robin"),
                        isHere: isHere,
                        showsDots: isHere && isTyping
                    )
                }
                .padding(PaeoniaSpacing.screenHorizontalPadding)
            }
            .navigationTitle(Text(verbatim: "Presence checks"))
            .navigationBarTitleDisplayMode(.inline)
            .paeoniaScreenBackground()
            .environment(\.dynamicTypeSize, largerText ? .accessibility3 : .large)
        }
    }
}
#endif

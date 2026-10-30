#if DEBUG
import SwiftUI

nonisolated extension DeveloperScenario {
    static let gamePresenceControls = DeveloperScenario(
        "game-presence-controls", "Game presence controls",
        "Toggle presence and recreate portraits. Use Settings to change Reduce Motion.", .games
    ) { _ in DeveloperGamePresenceScenario() }
}

/// Interactive checks of the production status components without network state.
private struct DeveloperGamePresenceScenario: View {
    @State private var isHere = false
    @State private var isTyping = false
    @State private var isLocked = false
    @State private var largerText = false
    @State private var portraitGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space24) {
                    Toggle("Partner here", isOn: $isHere)
                        .accessibilityIdentifier("presence.here")
                    Toggle("Writing signal", isOn: $isTyping)
                        .accessibilityIdentifier("presence.writing")
                    Toggle("Word locked", isOn: $isLocked)
                        .accessibilityIdentifier("presence.locked")
                    Toggle("Larger text", isOn: $largerText)
                        .accessibilityIdentifier("presence.largeText")
                    Button("Recreate portraits") { portraitGeneration += 1 }
                        .accessibilityIdentifier("presence.recreate")
                    statusRows.id(portraitGeneration)
                }
                .padding(PaeoniaSpacing.screenHorizontalPadding)
            }
            .navigationTitle(Text(verbatim: "Presence checks"))
            .navigationBarTitleDisplayMode(.inline)
            .paeoniaScreenBackground()
            .environment(\.dynamicTypeSize, largerText ? .accessibility3 : .large)
        }
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space24) {
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
                text: storyStatus,
                isHere: isHere,
                showsDots: isHere && isTyping
            )
            GamePresenceLabel(
                player: GamePlayer(name: "Robin", photoAssetID: nil),
                text: isHere ? .storyChainWriteHere("Robin") : .storyChainWaitGeneric("Robin"),
                isHere: isHere
            )
            .frame(maxWidth: .infinity)
            .animation(systemReduceMotion ? nil : PaeoniaMotion.stateChange, value: isHere)
        }
    }

    private var storyStatus: LocalizedStringResource {
        if !isHere { return .storyChainWaitGeneric("Robin") }
        return isTyping ? .storyChainWaitWriting("Robin") : .storyChainWriteHere("Robin")
    }
}
#endif

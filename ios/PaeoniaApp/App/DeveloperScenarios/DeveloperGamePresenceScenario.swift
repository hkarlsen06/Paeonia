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
    @State private var longName = false
    @State private var narrow = false
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
                    Toggle("Long partner name", isOn: $longName)
                    Toggle("Narrow play area", isOn: $narrow)
                    Button("Recreate portraits") { portraitGeneration += 1 }
                        .accessibilityIdentifier("presence.recreate")
                    statusRows
                        .frame(maxWidth: narrow ? 260 : .infinity)
                        .frame(maxWidth: .infinity)
                        .id(portraitGeneration)
                }
                .padding(PaeoniaSpacing.screenHorizontalPadding)
            }
            .navigationTitle(Text(verbatim: "Presence checks"))
            .navigationBarTitleDisplayMode(.inline)
            .paeoniaScreenBackground()
            .environment(\.dynamicTypeSize, largerText ? .accessibility3 : .large)
        }
    }

    private var partnerName: String { longName ? "Alvilde Alexandra Karlsen" : "Robin" }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space24) {
            activityRows
            StoryChainPartnerLine(
                participants: DeveloperGamesFixture.participants,
                text: storyStatus,
                isHere: isHere,
                showsDots: isHere && isTyping
            )
            GamePresenceLabel(
                player: GamePlayer(name: partnerName, photoAssetID: nil),
                text: isHere ? .storyChainWriteHere(partnerName) : .storyChainWaitGeneric(partnerName),
                isHere: isHere
            )
            .frame(maxWidth: .infinity)
            .animation(systemReduceMotion ? nil : PaeoniaMotion.stateChange, value: isHere)
        }
    }

    @ViewBuilder
    private var activityRows: some View {
        GameLiveRow {
            GamePresenceLabel(
                player: GamePlayer(name: partnerName, photoAssetID: nil),
                text: .exquisiteCorpseWaitDrawingNowBody(partnerName),
                isHere: isHere
            )
        } trailing: {
            EmptyView()
        }
        GameLiveRow {
            MindMeldPartnerStatusRow(
                partner: MindMeldPlayer(name: partnerName, photoAssetID: nil),
                status: isLocked ? .locked : isHere ? isTyping ? .typing : .here : .away,
                isPresent: isHere
            )
        } trailing: {
            Text(.mindMeldRound(2, 10)).font(PaeoniaTypography.caption)
        }
    }

    private var storyStatus: LocalizedStringResource {
        if !isHere { return .storyChainWaitGeneric(partnerName) }
        return isTyping ? .storyChainWaitWriting(partnerName) : .storyChainWriteHere(partnerName)
    }
}
#endif

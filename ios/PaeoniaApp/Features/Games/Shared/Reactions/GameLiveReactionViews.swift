import SwiftUI

struct GameLiveReactionAnchors: PreferenceKey {
    static var defaultValue: [GameLiveReaction: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [GameLiveReaction: Anchor<CGRect>],
        nextValue: () -> [GameLiveReaction: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct GameLiveReactionButtons: View {
    let isAvailable: Bool
    let identifierPrefix: String
    let send: (GameLiveReaction) -> Void

    var body: some View {
        if isAvailable {
            HStack(spacing: PaeoniaSpacing.space12) {
                ForEach(GameLiveReaction.allCases, id: \.self) { reaction in
                    Button {
                        send(reaction)
                    } label: {
                        Text(verbatim: reaction.glyph)
                            .font(PaeoniaTypography.title.bold())
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(.paeoniaTextPrimary)
                            .frame(
                                minWidth: PaeoniaSpacing.compactButtonHeight,
                                minHeight: PaeoniaSpacing.compactButtonHeight
                            )
                            .background(.paeoniaSurfaceSecondary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(reaction.label))
                    .accessibilityIdentifier("\(identifierPrefix).liveReaction.\(reaction.rawValue)")
                    .anchorPreference(key: GameLiveReactionAnchors.self, value: .bounds) { [reaction: $0] }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct GameFloatingReactions: View {
    let flights: [GameLiveReactionFlight]
    let anchors: [GameLiveReaction: Anchor<CGRect>]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origins: [GameLiveReaction: CGRect] = [:]

    var body: some View {
        GeometryReader { proxy in
            let currentOrigins = anchors.mapValues { proxy[$0] }
            TimelineView(.animation(paused: flights.isEmpty)) { timeline in
                ForEach(flights) { flight in
                    if let origin = origins[flight.reaction] {
                        let elapsed = timeline.date.timeIntervalSince(flight.start)
                        let progress = min(1, max(0, elapsed / GameLiveReactionFlight.duration))
                        Text(verbatim: flight.reaction.glyph)
                            .font(.system(size: PaeoniaSpacing.space40, weight: .bold, design: .rounded))
                            .foregroundStyle(.paeoniaTextPrimary)
                            .rotationEffect(.degrees(reduceMotion ? 0 : flight.tilt))
                            .scaleEffect(reduceMotion ? 1 : min(1, elapsed / 0.12))
                            .position(
                                x: origin.midX + (reduceMotion ? 0 : sin(progress * .pi) * flight.drift),
                                y: reduceMotion
                                    ? origin.minY - PaeoniaSpacing.space32
                                    : origin.midY - (origin.midY + PaeoniaSpacing.space40) * progress
                            )
                            .opacity(reduceMotion ? min(1, (1 - progress) * 4) : (progress < 1 ? 1 : 0))
                    }
                }
            }
            .onChange(of: currentOrigins, initial: true) { _, newValue in
                if !newValue.isEmpty { origins = newValue }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func gameLiveReactions(_ reactions: GameLiveReactions) -> some View {
        overlayPreferenceValue(GameLiveReactionAnchors.self) { anchors in
            GameFloatingReactions(flights: reactions.flights, anchors: anchors)
        }
        .toolbarBackground(reactions.flights.isEmpty ? .automatic : .hidden, for: .navigationBar)
    }
}

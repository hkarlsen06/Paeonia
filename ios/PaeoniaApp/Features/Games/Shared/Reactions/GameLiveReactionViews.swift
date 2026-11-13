import SwiftUI

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
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Reactions rise from the bottom of the screen, above the home indicator or
/// the keyboard, and leave through the top edge, the way live reactions do in a
/// video call. Reduce Motion shows each one at the bottom and fades it out.
struct GameFloatingReactions: View {
    let flights: [GameLiveReactionFlight]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let startY = proxy.size.height - proxy.safeAreaInsets.bottom - PaeoniaSpacing.space40
            let endY = -proxy.frame(in: .global).minY - PaeoniaSpacing.space40
            TimelineView(.animation(paused: flights.isEmpty)) { timeline in
                ForEach(flights) { flight in
                    let elapsed = timeline.date.timeIntervalSince(flight.start)
                    let progress = min(1, max(0, elapsed / GameLiveReactionFlight.duration))
                    Text(verbatim: flight.reaction.glyph)
                        .font(.system(size: PaeoniaSpacing.space40, weight: .bold, design: .rounded))
                        .foregroundStyle(.paeoniaTextPrimary)
                        .rotationEffect(.degrees(reduceMotion ? 0 : flight.tilt))
                        .scaleEffect(reduceMotion ? 1 : min(1, elapsed / 0.12))
                        .position(
                            x: proxy.size.width * flight.lane
                                + (reduceMotion ? 0 : sin(progress * .pi) * flight.drift),
                            y: reduceMotion ? startY : startY + (endY - startY) * progress
                        )
                        .opacity(reduceMotion ? min(1, (1 - progress) * 4) : (progress < 1 ? 1 : 0))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func gameLiveReactions(_ reactions: GameLiveReactions) -> some View {
        overlay { GameFloatingReactions(flights: reactions.flights) }
            .toolbarBackground(reactions.flights.isEmpty ? .automatic : .hidden, for: .navigationBar)
    }
}

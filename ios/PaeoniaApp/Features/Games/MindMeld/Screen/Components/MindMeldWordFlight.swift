import SwiftUI

/// Where a word of a revealed round sits on the screen: on its card in the reveal,
/// or on its chip under the next round's title.
nonisolated struct MindMeldWordSlot: Hashable {
    enum Place: Hashable {
        case card
        case chip
    }

    let roundID: UUID
    let isMine: Bool
    let place: Place
}

/// The frames of the word slots on screen, in the Mind Meld screen's coordinate space.
struct MindMeldWordFrames: PreferenceKey {
    static let space = "mindMeld.screen"
    static let defaultValue: [MindMeldWordSlot: CGRect] = [:]

    static func reduce(value: inout [MindMeldWordSlot: CGRect], nextValue: () -> [MindMeldWordSlot: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports where this word sits. Does nothing without a slot.
    func mindMeldWordSlot(_ slot: MindMeldWordSlot?) -> some View {
        background {
            if let slot {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MindMeldWordFrames.self,
                        value: [slot: proxy.frame(in: .named(MindMeldWordFrames.space))]
                    )
                }
            }
        }
    }
}

/// The two words of a missed round dropping from their cards onto the chips of
/// the next round. The screen runs the drop: each word falls, then squashes
/// as it hits and springs back.
struct MindMeldWordFlight: Equatable {
    let roundID: UUID
    let mine: String
    let theirs: String
    var myWordFell = false
    var partnerWordFell = false
    var myWordSquashed = false
    var partnerWordSquashed = false

    /// How long a card falls before it hits the screen.
    static let fallDuration: TimeInterval = 0.42
    /// The partner's card lands this much after mine, so the two landings read as two.
    static let partnerDelay: TimeInterval = 0.08
    /// How long the squash and bounce after the landing take.
    static let settleDuration: TimeInterval = 0.4
    /// Falls slow at first and hits fast, like under gravity.
    static let fall = Animation.timingCurve(0.5, 0, 0.85, 0.4, duration: fallDuration)
    /// How long a card takes to squash flat when it hits.
    static let squashDuration: TimeInterval = 0.05
    static let squash = Animation.linear(duration: squashDuration)
    static let settle = Animation.spring(duration: settleDuration, bounce: 0.45)

    func fell(isMine: Bool) -> Bool { isMine ? myWordFell : partnerWordFell }
    func squashed(isMine: Bool) -> Bool { isMine ? myWordSquashed : partnerWordSquashed }
}

/// Draws each word as its card, face up, high above the screen, and drops it onto
/// the chip under the next round's title. Its shadow tightens as it nears the
/// screen, and it squashes a little and bounces back when it lands. On the way the
/// corners round into a capsule and the border takes the partner's color. The real
/// chips stay hidden until it lands.
struct MindMeldWordFlightView: View {
    let flight: MindMeldWordFlight
    let frames: [MindMeldWordSlot: CGRect]

    /// The card's word is about this much larger than the chip's.
    private static let cardTextScale: CGFloat = 1.6

    var body: some View {
        ZStack {
            word(flight.mine, isMine: true)
            word(flight.theirs, isMine: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func word(_ word: String, isMine: Bool) -> some View {
        if let card = frames[MindMeldWordSlot(roundID: flight.roundID, isMine: isMine, place: .card)],
           let chip = frames[MindMeldWordSlot(roundID: flight.roundID, isMine: isMine, place: .chip)] {
            let fell = flight.fell(isMine: isMine)
            let squash: CGFloat = flight.squashed(isMine: isMine) ? 1 : 0
            let tint: Color = isMine ? .paeoniaPartnerOne : .paeoniaPartnerTwo
            let frame = fell ? chip : card
            let shape = RoundedRectangle(
                cornerRadius: fell ? chip.height / 2 : PaeoniaRadius.radius20,
                style: .continuous
            )
            // A long word shrinks on the card, so it never grows past the card's width.
            let textWidth = max(chip.width - PaeoniaSpacing.space32, 1)
            let cardScale = min(Self.cardTextScale, (card.width - PaeoniaSpacing.space24) / textWidth)
            Text(verbatim: word.localizedUppercase)
                .font(PaeoniaTypography.bodyEmphasis)
                .tracking(0.5)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.paeoniaTextPrimary)
                .scaleEffect(fell ? 1 : cardScale)
                .frame(width: frame.width, height: frame.height)
                .background(fell ? Color.paeoniaSurfaceSecondary : .paeoniaSurfacePrimary, in: shape)
                .overlay {
                    shape.strokeBorder(tint.opacity(fell ? 0.55 : 0), lineWidth: PaeoniaRadius.strokeDefault)
                }
                // High above the screen the shadow is wide and soft. On the screen it is tight.
                .shadow(color: .black.opacity(fell ? 0.18 : 0.4), radius: fell ? 2 : 18, y: fell ? 1 : 10)
                .scaleEffect(x: 1 + 0.08 * squash, y: 1 - 0.12 * squash, anchor: .bottom)
                .position(x: frame.midX, y: frame.midY)
        }
    }
}

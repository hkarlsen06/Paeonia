import SwiftUI

/// The two word cards of the reveal, each with an avatar above it, the glow behind
/// them and the petal bloom. It draws what its inputs say and keeps no timeline. The
/// reveal script changes the inputs, and the stage animates each change.
///
/// - My card is on the leading side.
/// - `merged` slides the cards together, and `joined` says they touched. Then the
///   card thumps, its border turns green, and only my card shows. The two avatars
///   move together above it.
/// - `bloomStart` plays one burst. The script clears it when the burst is over,
///   because the bloom keeps redrawing while it is set.
/// - With Reduce Motion there are no pulses, slides or bloom. Cards cross-fade and
///   the other states change at once.
struct MindMeldRevealStage: View {
    typealias Person = (name: String, photoAssetID: UUID?)

    let me: Person
    let partner: Person
    let myWord: String
    let partnerWord: String
    let myCardFlipped: Bool
    let partnerCardFlipped: Bool
    /// Each increase pulses both cards once.
    let pulse: Int
    let merged: Bool
    let joined: Bool
    /// The cards lean toward each other, for words that are almost the same.
    let leaning: Bool
    /// A thin line with a plus draws between the cards.
    let linkDrawn: Bool
    /// The strength of the glow behind the cards, from 0 to 1.
    let glow: Double
    let bloomStart: Date?
    let seed: String
    var cardMaxWidth: CGFloat = 160
    /// The round on the cards. The cards report where they sit, so the screen
    /// can fly the words into the next round's chips.
    var roundID: UUID?

    private static let avatarSize: CGFloat = 44
    private static let bloomIntensity: CGFloat = 1.6
    private static let flip = Animation.spring(duration: 0.4, bounce: 0.14)
    /// The cards reach for each other, nearly touch, and settle a little apart.
    private static let lean = Animation.spring(duration: 0.5, bounce: 0.4)
    /// How far the merged card swells when the cards touch.
    private static let thumpScale: CGFloat = 1.07

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MindMeldStageLayout(merge: merged ? 1 : 0, lean: leaning ? 1 : 0, maxCardWidth: cardMaxWidth) {
            avatar(me, tint: .paeoniaPartnerOne)
            avatar(partner, tint: .paeoniaPartnerTwo)
            myCard
            partnerCard
            MindMeldRevealLink(isDrawn: linkDrawn)
                .zIndex(2)
        }
        .motionOnly(MindMeldRevealTimeline.slide, value: merged)
        .motionOnly(Self.lean, value: leaning)
        .background { glowView }
        .overlay { bloom }
    }

    private var tone: MindMeldWordCard.Tone {
        if joined { .success } else if leaning { .near } else { .plain }
    }

    // MARK: Cards

    private var myCard: some View {
        MindMeldWordCard(
            word: myWord,
            isFaceUp: myCardFlipped,
            faceDownLabel: .mindMeldWaitYourWordA11Y(myWord.localizedUppercase),
            tone: tone,
            maxWidth: cardMaxWidth
        )
        .motionOnly(Self.flip, value: myCardFlipped)
        .modifier(MindMeldPulse(trigger: pulse, peak: pulsePeak))
        .modifier(MindMeldPulse(trigger: joined, peak: Self.thumpScale))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(myCardLabel))
        .mindMeldWordSlot(roundID.map { MindMeldWordSlot(roundID: $0, isMine: true, place: .card) })
        // On top of the partner's card once they are one.
        .zIndex(1)
    }

    /// The partner's card stays solid while it slides under mine, and hides once they touch.
    private var partnerCard: some View {
        MindMeldWordCard(
            word: partnerWord,
            isFaceUp: partnerCardFlipped,
            faceDownLabel: .mindMeldRevealCardFacedownA11Y(partner.name),
            tone: tone,
            maxWidth: cardMaxWidth
        )
        .motionOnly(Self.flip, value: partnerCardFlipped)
        .opacity(joined ? 0 : 1)
        .modifier(MindMeldPulse(trigger: pulse, peak: pulsePeak))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(partnerCardLabel))
        .mindMeldWordSlot(roundID.map { MindMeldWordSlot(roundID: $0, isMine: false, place: .card) })
    }

    /// Each pulse swells the cards a little more than the last.
    private var pulsePeak: CGFloat {
        1.02 + 0.015 * CGFloat(pulse)
    }

    private var myCardLabel: LocalizedStringResource {
        myCardFlipped
            ? .mindMeldRevealCardA11Y(String(localized: .mindMeldRevealYou), myWord.localizedUppercase)
            : .mindMeldWaitYourWordA11Y(myWord.localizedUppercase)
    }

    private var partnerCardLabel: LocalizedStringResource {
        partnerCardFlipped
            ? .mindMeldRevealCardA11Y(partner.name, partnerWord.localizedUppercase)
            : .mindMeldRevealCardFacedownA11Y(partner.name)
    }

    private func avatar(_ person: Person, tint: Color) -> some View {
        PaeoniaProfilePhotoAvatar(
            mediaAssetID: person.photoAssetID,
            name: person.name,
            tint: tint,
            size: Self.avatarSize
        )
        .accessibilityHidden(true)
    }

    // MARK: Glow and bloom

    /// How far the middle of the cards sits below the middle of the stage.
    private var cardCenterOffset: CGFloat {
        (Self.avatarSize + MindMeldStageLayout.avatarGap) / 2
    }

    private var glowView: some View {
        EllipticalGradient(
            colors: [.paeoniaAccentPrimary, .clear],
            center: .center,
            startRadiusFraction: 0.06,
            endRadiusFraction: 0.5
        )
        .frame(width: cardMaxWidth * 4.4, height: cardMaxWidth * 3)
        .opacity(glow)
        .animation(PaeoniaMotion.meaningfulMoment, value: glow)
        .offset(y: cardCenterOffset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var bloom: some View {
        if let bloomStart, !reduceMotion {
            // Bigger than the stage, so the petals can fly past the cards.
            GamePetalBloom(start: bloomStart, seed: seed, intensity: Self.bloomIntensity)
                .frame(width: cardMaxWidth * 4.5, height: cardMaxWidth * 2.6)
                .offset(y: cardCenterOffset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Layout

/// Places the avatars, the cards and the link. The subviews, in order, are my
/// avatar, the partner's avatar, my card, the partner's card and the link.
/// `merge` runs from 0 (side by side) to 1 (one card) and `lean` from 0 to 1
/// (each card 13 pt toward the other). Both animate, so the cards slide.
private struct MindMeldStageLayout: Layout {
    var merge: CGFloat
    var lean: CGFloat
    let maxCardWidth: CGFloat

    static let cardGap = PaeoniaSpacing.space40
    static let avatarGap = PaeoniaSpacing.space12
    private static let leanDistance: CGFloat = 13
    /// Half the distance between the two avatar centers once the cards are one.
    private static let mergedAvatarSpread: CGFloat = 20

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(merge, lean) }
        set {
            merge = newValue.first
            lean = newValue.second
        }
    }

    private struct Metrics {
        let cardWidth: CGFloat
        let cardHeight: CGFloat
        let avatarHeight: CGFloat
    }

    private func metrics(width: CGFloat?, subviews: Subviews) -> Metrics {
        let available = width ?? (2 * maxCardWidth + Self.cardGap)
        let cardWidth = max(0, min(maxCardWidth, (available - Self.cardGap) / 2))
        let proposal = ProposedViewSize(width: cardWidth, height: nil)
        return Metrics(
            cardWidth: cardWidth,
            cardHeight: max(subviews[2].sizeThatFits(proposal).height, subviews[3].sizeThatFits(proposal).height),
            avatarHeight: subviews[0].sizeThatFits(.unspecified).height
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let metrics = metrics(width: proposal.width, subviews: subviews)
        return CGSize(
            width: 2 * metrics.cardWidth + Self.cardGap,
            height: metrics.avatarHeight + Self.avatarGap + metrics.cardHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let metrics = metrics(width: bounds.width, subviews: subviews)
        let center = bounds.midX
        let reach = (metrics.cardWidth + Self.cardGap) / 2
        let pull = lean * Self.leanDistance
        let myApart = center - reach + pull
        let partnerApart = center + reach - pull
        let cardTop = bounds.minY + metrics.avatarHeight + Self.avatarGap

        subviews[0].place(
            at: CGPoint(x: mix(myApart, center - Self.mergedAvatarSpread), y: bounds.minY),
            anchor: .top,
            proposal: .unspecified
        )
        subviews[1].place(
            at: CGPoint(x: mix(partnerApart, center + Self.mergedAvatarSpread), y: bounds.minY),
            anchor: .top,
            proposal: .unspecified
        )
        let cardProposal = ProposedViewSize(width: metrics.cardWidth, height: metrics.cardHeight)
        subviews[2].place(at: CGPoint(x: mix(myApart, center), y: cardTop), anchor: .top, proposal: cardProposal)
        subviews[3].place(at: CGPoint(x: mix(partnerApart, center), y: cardTop), anchor: .top, proposal: cardProposal)
        subviews[4].place(
            at: CGPoint(x: center, y: cardTop + metrics.cardHeight / 2),
            anchor: .center,
            proposal: ProposedViewSize(width: Self.cardGap, height: nil)
        )
    }

    /// From `apart` at merge 0 to `together` at merge 1.
    private func mix(_ apart: CGFloat, _ together: CGFloat) -> CGFloat {
        apart + (together - apart) * merge
    }
}

// MARK: - Link

/// A thin line between the cards with a plus in a circle. The line draws from the
/// left, then the plus pops in.
private struct MindMeldRevealLink: View {
    let isDrawn: Bool

    private static let badgeSize: CGFloat = 22

    var body: some View {
        ZStack {
            MindMeldLinkLine()
                .trim(from: 0, to: isDrawn ? 1 : 0)
                .stroke(
                    Color.paeoniaAccentPrimary.opacity(0.7),
                    style: StrokeStyle(lineWidth: PaeoniaRadius.strokeEmphasis, lineCap: .round)
                )
                .motionOnly(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionMorph), value: isDrawn)
            Image(systemName: "plus")
                .accessibilityHidden(true)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: Self.badgeSize, height: Self.badgeSize)
                .background(.paeoniaSurfacePrimary, in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        Color.paeoniaAccentPrimary.opacity(0.7),
                        lineWidth: PaeoniaRadius.strokeDefault
                    )
                )
                .scaleEffect(isDrawn ? 1 : 0.4)
                .opacity(isDrawn ? 1 : 0)
                .motionOnly(PaeoniaMotion.cardReveal.delay(PaeoniaMotion.motionMorph / 2), value: isDrawn)
        }
        .frame(height: Self.badgeSize)
        .accessibilityHidden(true)
    }
}

nonisolated private struct MindMeldLinkLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

// MARK: - Motion helpers

/// The card grows to `peak` and settles back each time `trigger` changes.
private struct MindMeldPulse<Trigger: Equatable & Sendable>: ViewModifier {
    let trigger: Trigger
    let peak: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(peak, duration: 0.12)
                    CubicKeyframe(1.0, duration: 0.16)
                }
            }
        }
    }
}

/// Animates changes of `value`, except under Reduce Motion, where they happen at once.
private struct MotionOnly<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.animation(animation, value: value)
        }
    }
}

private extension View {
    func motionOnly(_ animation: Animation, value: some Equatable) -> some View {
        modifier(MotionOnly(animation: animation, value: value))
    }
}

#if DEBUG
private let previewMe: MindMeldRevealStage.Person = (name: "Alex", photoAssetID: nil)
private let previewPartner: MindMeldRevealStage.Person = (name: "Robin", photoAssetID: nil)

private struct MindMeldRevealStagePreview: View {
    var myWord = "Ocean"
    var partnerWord = "Sushi"
    var flipped = true
    var merged = false
    var leaning = false
    var linkDrawn = false
    var glow = 0.16

    var body: some View {
        MindMeldRevealStage(
            me: previewMe,
            partner: previewPartner,
            myWord: myWord,
            partnerWord: partnerWord,
            myCardFlipped: flipped,
            partnerCardFlipped: flipped,
            pulse: 0,
            merged: merged,
            joined: merged,
            leaning: leaning,
            linkDrawn: linkDrawn,
            glow: glow,
            bloomStart: nil,
            seed: "preview"
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
    }
}

#Preview("Face down") {
    MindMeldRevealStagePreview(flipped: false)
}

#Preview("Miss with link") {
    MindMeldRevealStagePreview(linkDrawn: true, glow: 0.3)
}

#Preview("Near miss leaning") {
    MindMeldRevealStagePreview(partnerWord: "Oceans", leaning: true, glow: 0.3)
}

#Preview("Merged") {
    MindMeldRevealStagePreview(partnerWord: "Ocean", merged: true, glow: 0.4)
}

#Preview("Accessibility text") {
    MindMeldRevealStagePreview(partnerWord: "Ice cream", linkDrawn: true)
        .dynamicTypeSize(.accessibility3)
}

/// Tap to play the meld: the cards slide together and the petals burst.
#Preview("Meld in motion") {
    @Previewable @State var merged = false
    @Previewable @State var bloomStart: Date?
    VStack(spacing: PaeoniaSpacing.space32) {
        MindMeldRevealStage(
            me: previewMe,
            partner: previewPartner,
            myWord: "Fish",
            partnerWord: "Fish",
            myCardFlipped: true,
            partnerCardFlipped: true,
            pulse: 0,
            merged: merged,
            joined: merged,
            leaning: false,
            linkDrawn: false,
            glow: merged ? 0.4 : 0.16,
            bloomStart: bloomStart,
            seed: "preview"
        )
        Button {
            merged.toggle()
            bloomStart = merged ? .now : nil
        } label: {
            Text(verbatim: merged ? "Reset" : "Meld")
        }
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif

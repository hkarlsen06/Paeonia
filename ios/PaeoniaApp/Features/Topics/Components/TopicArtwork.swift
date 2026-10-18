import SwiftUI

/// Each topic's own tint, washed over the plum card. A topic the app doesn't know yet
/// uses the accent, so a topic added on the server still shows.
enum TopicStyle {
    static func tint(for key: String) -> Color {
        switch key {
        case "getting_to_know_you": .paeoniaInkLavender
        case "whos_more_likely": .paeoniaInkGold
        case "would_you_rather": .paeoniaSuccess
        case "travel_and_places": .paeoniaInkBlue
        case "someday": .paeoniaWarning
        case "flirt": .paeoniaAccentSecondary
        default: .paeoniaAccentPrimary
        }
    }
}

/// A topic's illustrated object, in the house 3D sticker style, with its one small
/// moment (the beat). The beat plays once when the picture appears. Reduce Motion
/// keeps every picture still. Anchor points are fractions of the imported images,
/// measured from their pixels (see the paeonia-illustrations skill).
struct TopicArtwork: View {
    let topicKey: String
    let height: CGFloat
    /// False where many pictures sit together and the movement would be too much.
    var playsBeat = true
    /// The adults-only topic before both partners confirmed: the picture shows soft.
    var isFrosted = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = 0

    var body: some View {
        artwork
            .blur(radius: isFrosted ? height * 0.06 : 0)
            .saturation(isFrosted ? 0.7 : 1)
            .accessibilityHidden(true)
            .task {
                guard playsBeat, !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                beat += 1
            }
    }

    @ViewBuilder
    private var artwork: some View {
        switch topicKey {
        case "getting_to_know_you": nestingDoll
        case "whos_more_likely": spinner
        case "would_you_rather": sweets
        case "travel_and_places": suitcase
        case "someday": balloon
        case "flirt": cherries
        default:
            Image(.gameHubPeony)
                .resizable()
                .accessibilityHidden(true)
                .scaledToFit()
                .frame(height: height)
        }
    }

    // MARK: - Getting to know you

    /// The doll's top half lifts and a smaller doll peeks out, then it closes.
    private var nestingDoll: some View {
        let height = height
        let width = height * 0.6911
        let seam = height * 0.4777
        return ZStack(alignment: .topLeading) {
            Image(.topicKnowDollSmall)
                .resizable()
                .accessibilityHidden(true)
                .frame(width: height * 0.40 * 0.823, height: height * 0.40)
                .offset(x: (width - height * 0.40 * 0.823) / 2, y: seam - height * 0.32)
            Image(.topicKnowDollBottom)
                .resizable()
                .accessibilityHidden(true)
                .frame(width: width, height: height - seam)
                .offset(y: seam)
            Image(.topicKnowDollTop)
                .resizable()
                .accessibilityHidden(true)
                .frame(width: width * 0.8548, height: seam)
                .offset(x: width * 0.0726)
                .keyframeAnimator(initialValue: 0.0, trigger: beat) { content, lift in
                    content.offset(y: -lift * height)
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(0.27, duration: 0.45, spring: .bouncy)
                        LinearKeyframe(0.27, duration: 0.8)
                        SpringKeyframe(0, duration: 0.5, spring: .snappy)
                    }
                }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    // MARK: - Who's more likely

    /// The arrow spins on the dial and settles on one of the two halves.
    private var spinner: some View {
        let size = height
        let arrowHeight = size * 0.62
        let hub = UnitPoint(x: 0.4993, y: 0.7275)
        return ZStack {
            Image(.topicLikelyDial)
                .resizable()
                .accessibilityHidden(true)
                .frame(width: size, height: size)
            Image(.topicLikelyArrow)
                .resizable()
                .accessibilityHidden(true)
                .frame(width: arrowHeight * 0.547, height: arrowHeight)
                .keyframeAnimator(initialValue: -35.0, trigger: beat) { content, angle in
                    content.rotationEffect(.degrees(angle), anchor: hub)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(560, duration: 1.0)
                        SpringKeyframe(685, duration: 0.7, spring: .bouncy)
                    }
                }
                // Puts the hub on the dial's center.
                .offset(y: (0.5 - hub.y) * arrowHeight)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Would you rather

    /// Two sweets held out to choose from. Each hops once.
    private var sweets: some View {
        let width = height * 1.5
        let sweetWidth = width * 0.72
        return ZStack {
            sweet(.topicWyrSweetGold, width: sweetWidth, delay: 0)
                .offset(x: -width * 0.12, y: -height * 0.17)
            sweet(.topicWyrSweetBlue, width: sweetWidth, delay: 0.25)
                .offset(x: width * 0.12, y: height * 0.17)
        }
        .frame(width: width, height: height)
    }

    private func sweet(_ image: ImageResource, width: CGFloat, delay: Double) -> some View {
        let hop = height * 0.14
        return Image(image)
            .resizable()
            .accessibilityHidden(true)
            .frame(width: width, height: width / 3)
            .keyframeAnimator(initialValue: 0.0, trigger: beat) { content, lift in
                content.offset(y: -lift * hop)
            } keyframes: { _ in
                KeyframeTrack {
                    // A keyframe of no length gives the animation no valid value and
                    // the sweet disappears, so the wait is never zero.
                    LinearKeyframe(0, duration: max(delay, 0.05))
                    SpringKeyframe(1, duration: 0.25, spring: .snappy)
                    SpringKeyframe(0, duration: 0.45, spring: .bouncy)
                }
            }
    }

    // MARK: - Travel and places

    /// The luggage tag swings on its string from the handle.
    private var suitcase: some View {
        let width = height * 1.197
        let tagHeight = height * 0.46
        let tagWidth = tagHeight * 0.421
        let handle = CGPoint(x: width * 0.3253, y: height * 0.1957)
        return ZStack(alignment: .topLeading) {
            Image(.topicTravelSuitcase)
                .resizable()
                .accessibilityHidden(true)
                .frame(width: width, height: height)
            Image(.topicTravelTag)
                .resizable()
                .accessibilityHidden(true)
                .frame(width: tagWidth, height: tagHeight)
                .keyframeAnimator(initialValue: 4.0, trigger: beat) { content, angle in
                    content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.4928, y: 0))
                } keyframes: { _ in
                    KeyframeTrack {
                        SpringKeyframe(18, duration: 0.3)
                        SpringKeyframe(-11, duration: 0.4)
                        SpringKeyframe(9, duration: 0.4)
                        SpringKeyframe(4, duration: 0.5)
                    }
                }
                // The top of the string loop hangs on the handle.
                .offset(x: handle.x - tagWidth * 0.4928, y: handle.y)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    // MARK: - Someday

    /// The balloon floats up and down, slowly.
    private var balloon: some View {
        let image = Image(.topicSomedayBalloon)
            .resizable()
            .accessibilityHidden(true)
            .frame(width: height * 0.6826, height: height)
        return Group {
            if playsBeat, !reduceMotion {
                image.phaseAnimator([0.0, 1.0]) { content, phase in
                    content.offset(y: -phase * height * 0.05)
                } animation: { _ in
                    .easeInOut(duration: 2.4)
                }
            } else {
                image
            }
        }
    }

    // MARK: - Flirt

    /// The cherries swing on their stem.
    private var cherries: some View {
        Image(.topicFlirtCherries)
            .resizable()
            .accessibilityHidden(true)
            .frame(width: height * 1.0353, height: height)
            .keyframeAnimator(initialValue: 0.0, trigger: beat) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.4865, y: 0.0024))
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(10, duration: 0.3)
                    SpringKeyframe(-7, duration: 0.4)
                    SpringKeyframe(3, duration: 0.4)
                    SpringKeyframe(0, duration: 0.5)
                }
            }
    }
}

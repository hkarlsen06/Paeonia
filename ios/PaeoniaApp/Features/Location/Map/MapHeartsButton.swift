import SwiftUI

/// The heart row on the compact Home card, for couples who have no map. Both
/// avatars sit with a glossy heart between them. A tap squishes the heart, plays a soft
/// sound and a tap on the phone, and sends a heart. The partner's hearts fly back to the
/// person's avatar here. The heart beats once when the row first appears.
struct MapHeartsButton: View {
    let currentName: String
    let currentProfilePhotoAssetID: UUID?
    let partnerName: String
    let partnerProfilePhotoAssetID: UUID?
    let incomingBurst: HeartsBurst?
    let onSend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flights = HeartFlights()
    @State private var tapCount = 0
    @State private var beatCount = 0
    @State private var hasBeaten = false

    private static let avatarDiameter: CGFloat = 36
    private static let heartGap: CGFloat = 28
    /// The heart overlaps both avatars a little. The art is imported for about 50 pt.
    private static let heartWidth: CGFloat = 40
    private static let width = avatarDiameter * 2 + heartGap

    var body: some View {
        Button {
            tapCount += 1
            GameSound.send.play(volume: 0.5)
            flights.send()
            onSend()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .onChange(of: incomingBurst) { _, burst in
            if let burst {
                flights.receive(count: burst.flyingCount)
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: tapCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(.heartsSendAction))
        .accessibilityHint(Text(.heartsSendHint(partnerName)))
        .task {
            guard !reduceMotion, !hasBeaten else { return }
            hasBeaten = true
            try? await Task.sleep(for: .milliseconds(600))
            beatCount += 1
        }
    }

    private var label: some View {
        HStack(spacing: Self.heartGap) {
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: currentProfilePhotoAssetID,
                name: currentName,
                tint: .paeoniaPartnerOne,
                size: Self.avatarDiameter
            )
            PaeoniaProfilePhotoAvatar(
                mediaAssetID: partnerProfilePhotoAssetID,
                name: partnerName,
                tint: .paeoniaPartnerTwo,
                size: Self.avatarDiameter
            )
        }
        .overlay { GlossyHeart(width: Self.heartWidth, tapCount: tapCount, beatCount: beatCount) }
        .frame(width: Self.width, height: PaeoniaSpacing.compactButtonHeight)
        .contentShape(Rectangle())
        // Hearts fly over the whole button, and past its edge on a wide arc.
        .overlay {
            KissLayer(
                start: CGPoint(x: Self.avatarDiameter / 2, y: PaeoniaSpacing.compactButtonHeight / 2),
                end: CGPoint(x: Self.width - Self.avatarDiameter / 2, y: PaeoniaSpacing.compactButtonHeight / 2),
                tapKisses: flights.kisses,
                showsAmbient: false
            )
        }
    }
}

/// The glossy heart that sends hearts. It squishes on each new `tapCount` and beats once
/// on each new `beatCount`.
struct GlossyHeart: View {
    let width: CGFloat
    var tapCount = 0
    var beatCount = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Squashes flat and wide, then stretches tall, then settles. Used for each tap.
    private struct Squish {
        var x = 1.0
        var y = 1.0
    }

    var body: some View {
        Image(.homeHeart)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .keyframeAnimator(initialValue: Squish(), trigger: reduceMotion ? 0 : tapCount) { view, squish in
                view.scaleEffect(x: squish.x, y: squish.y)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    CubicKeyframe(1.22, duration: 0.08)
                    CubicKeyframe(0.92, duration: 0.12)
                    SpringKeyframe(1, duration: 0.3, spring: .bouncy)
                }
                KeyframeTrack(\.y) {
                    CubicKeyframe(0.76, duration: 0.08)
                    CubicKeyframe(1.16, duration: 0.12)
                    SpringKeyframe(1, duration: 0.3, spring: .bouncy)
                }
            }
            // A lub-dub, once.
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : beatCount) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.16, duration: 0.12)
                    CubicKeyframe(1, duration: 0.12)
                    CubicKeyframe(1.1, duration: 0.12)
                    CubicKeyframe(1, duration: 0.3)
                }
            }
            .accessibilityHidden(true)
    }
}

/// "Robin sent you 14 hearts" while the partner's hearts play.
struct HeartsIncomingLine: View {
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "heart.fill")
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.caption.weight(.semibold))
        .foregroundStyle(.paeoniaAccentPrimary)
    }
}

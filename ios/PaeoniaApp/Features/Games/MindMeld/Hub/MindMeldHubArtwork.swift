import SwiftUI

/// The picture at the top of the Mind Meld card: two glowing circles, each holding
/// a word, drift together. Where they overlap, a few petals open and the two words
/// become one tile with a petal on it. It plays once when the card appears. With
/// Reduce Motion it starts finished.
struct MindMeldHubArtwork: View {
    static let height: CGFloat = 200
    private static let startDelay: TimeInterval = 0.3
    private static let driftDuration: TimeInterval = 2.4
    private static let circleSize: CGFloat = 96
    /// How far each circle sits from the middle before and after the drift.
    private static let spreadApart: CGFloat = 0.27
    private static let spreadTogether: CGFloat = 0.075
    private static let bloomSeed = "mind-meld-hub"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasPlayed = false
    @State private var hasDrifted = false
    @State private var isMerged = false
    @State private var bloomStart: Date?

    var body: some View {
        ZStack {
            background
            scene
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        // The art is a picture, so it keeps its size at every text size.
        .dynamicTypeSize(.large)
        .clipped()
        .accessibilityHidden(true)
        .task { await play() }
    }

    // MARK: Timeline

    private func play() async {
        guard !hasPlayed else { return }
        hasPlayed = true
        guard !reduceMotion else {
            settle()
            return
        }
        do {
            try await Task.sleep(for: .seconds(Self.startDelay))
            withAnimation(PaeoniaMotion.standardCurve(duration: Self.driftDuration)) { hasDrifted = true }
            // The circles touch a little before the drift ends.
            try await Task.sleep(for: .seconds(Self.driftDuration * 0.85))
            bloomStart = .now
            withAnimation(PaeoniaMotion.celebrationReveal) { isMerged = true }
            try await Task.sleep(for: .seconds(GamePetalBloom.duration + 0.1))
            bloomStart = nil
        } catch {
            // The card left the screen. It shows the finished picture when it comes back.
            settle()
        }
    }

    private func settle() {
        hasDrifted = true
        isMerged = true
        bloomStart = nil
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [.paeoniaSurfacePressed, .paeoniaBackgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.45), .clear],
                center: UnitPoint(x: 0.85, y: 0.1),
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [Color.paeoniaInkLavender.opacity(0.3), .clear],
                center: UnitPoint(x: 0.05, y: 0.95),
                startRadius: 0,
                endRadius: 200
            )
        }
    }

    // MARK: Scene

    private var scene: some View {
        GeometryReader { proxy in
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.54)
            let spread = proxy.size.width * (hasDrifted ? Self.spreadTogether : Self.spreadApart)
            ZStack {
                meetingGlow
                    .position(middle)
                circle(tint: .paeoniaPartnerOne, word: .mindMeldHubArtworkFirst, tilt: -6)
                    .position(x: middle.x - spread, y: middle.y)
                circle(tint: .paeoniaPartnerTwo, word: .mindMeldHubArtworkSecond, tilt: 5)
                    .position(x: middle.x + spread, y: middle.y)
                mergedTile
                    .position(middle)
                if let bloomStart {
                    GamePetalBloom(start: bloomStart, seed: Self.bloomSeed, intensity: 0.7)
                        .frame(width: 300, height: Self.height)
                        .position(middle)
                }
                sparkles(in: proxy.size)
            }
        }
    }

    /// A soft light where the circles meet. It grows when the words become one.
    private var meetingGlow: some View {
        RadialGradient(
            colors: [.paeoniaAccentPrimary.opacity(0.55), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 80
        )
        .frame(width: 160, height: 160)
        .opacity(isMerged ? 1 : 0)
        .scaleEffect(isMerged ? 1 : 0.4)
    }

    /// One soft circle in a partner's color with that partner's word on a tile.
    private func circle(tint: Color, word: LocalizedStringResource, tilt: Double) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.4))
                .blur(radius: 20)
                .scaleEffect(1.2)
                .blendMode(.plusLighter)
            Circle()
                .fill(RadialGradient(
                    colors: [tint.opacity(0.5), tint.opacity(0.14)],
                    center: .center,
                    startRadius: 0,
                    endRadius: Self.circleSize / 2
                ))
                .blendMode(.plusLighter)
            Circle()
                .strokeBorder(tint.opacity(0.7), lineWidth: PaeoniaRadius.strokeEmphasis)
            Text(word)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.paeoniaTextInverse)
                .fixedSize()
                .padding(.horizontal, PaeoniaSpacing.space12)
                .padding(.vertical, PaeoniaSpacing.space8)
                .background(
                    Color.paeoniaTextPrimary,
                    in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius8, style: .continuous)
                )
                .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 6, y: 3)
                .rotationEffect(.degrees(tilt))
                .opacity(isMerged ? 0 : 1)
                .scaleEffect(isMerged ? 0.5 : 1)
        }
        .frame(width: Self.circleSize, height: Self.circleSize)
        .scaleEffect(isMerged ? 1.05 : 1)
    }

    /// The two words as one tile with a petal on it.
    private var mergedTile: some View {
        MindMeldPetalMark()
            .frame(width: 28, height: 28)
            .foregroundStyle(.paeoniaAccentSecondary)
            .frame(width: 50, height: 50)
            .background(
                Color.paeoniaTextPrimary,
                in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous)
            )
            .shadow(color: .paeoniaBackgroundSecondary.opacity(0.5), radius: 8, y: 4)
            .rotationEffect(.degrees(isMerged ? 0 : -8))
            .scaleEffect(isMerged ? 1 : 0.4)
            .opacity(isMerged ? 1 : 0)
    }

    // MARK: Sparkles

    private struct Sparkle {
        let size: CGFloat
        let color: Color
        let x: CGFloat
        let y: CGFloat
    }

    private static let sparkles = [
        Sparkle(size: 13, color: .paeoniaInkGold, x: 0.07, y: 0.24),
        Sparkle(size: 9, color: .paeoniaTextSecondary, x: 0.9, y: 0.3),
        Sparkle(size: 11, color: .paeoniaTextPrimary, x: 0.86, y: 0.84),
        Sparkle(size: 8, color: .paeoniaInkGold, x: 0.16, y: 0.86),
    ]

    private func sparkles(in size: CGSize) -> some View {
        ForEach(Self.sparkles.indices, id: \.self) { index in
            let sparkle = Self.sparkles[index]
            Image(systemName: "sparkle")
                .accessibilityHidden(true)
                .font(.system(size: sparkle.size, weight: .bold))
                .foregroundStyle(sparkle.color)
                .opacity(isMerged ? 1 : 0)
                .scaleEffect(isMerged ? 1 : 0.3)
                .position(x: size.width * sparkle.x, y: size.height * sparkle.y)
        }
    }
}

#if DEBUG
#Preview {
    MindMeldHubArtwork()
        .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius28, style: .continuous))
        .padding()
        .background(.paeoniaBackgroundPrimary)
}
#endif

import Foundation
import SwiftUI

/// The cinematic moment shown the instant two people become linked.
///
/// A heart forms in the middle of the screen and pulls a swirling field of
/// particles inward like a small gravity well, while soft haptic pulses build in
/// pressure. At the climax the core bursts outward and the burst reveals the
/// partner's avatar at the center; it then glides into place beside the current
/// person, and the connecting line, heart, and names settle into view.
///
/// The whole intro plays only when `playsIntro` is true and Reduce Motion is off.
/// Otherwise the final, settled state is shown immediately so the screen never
/// looks broken and the moment is never replayed on an ordinary app open.
struct PairingCelebrationView: View { // swiftlint:disable:this type_body_length
    private static let coordinateSpace = "pairingCelebration"
    private let heroScale: CGFloat = 1.45

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: PairingCelebrationPhase = .heartAppearing
    @State private var introMode: IntroMode = .undecided
    @State private var animationStart = Date()
    @State private var hasStarted = false
    @State private var driver: Task<Void, Never>?

    @State private var heartScale: CGFloat = 0.2
    @State private var heartOpacity: Double = 0
    @State private var heartGlow: CGFloat = 12

    @State private var partnerRevealed = false
    @State private var partnerOpacity: Double = 0
    @State private var partnerScale: CGFloat = 0.5
    @State private var partnerLanded = false
    @State private var partnerGlow: CGFloat = 24
    @State private var partnerSlot: CGRect = .zero

    @State private var surroundingsShown = false
    @State private var currentProfilePhotoData: Data?
    @State private var partnerProfilePhotoData: Data?
    @State private var currentProfilePhotoLoadFinished = false
    @State private var partnerProfilePhotoLoadFinished = false
    @State private var currentProfilePhotoLoadTask: Task<Void, Never>?
    @State private var partnerProfilePhotoLoadTask: Task<Void, Never>?

    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
    let partnerDisplayName: String?
    let partnerProfilePhotoAssetID: UUID?
    let playsIntro: Bool
    let onIntroComplete: () -> Void
    private let profilePhotoProvider: any ProfilePhotoImageProviding

    init(
        currentDisplayName: String?,
        currentProfilePhotoAssetID: UUID? = nil,
        partnerDisplayName: String? = nil,
        partnerProfilePhotoAssetID: UUID? = nil,
        playsIntro: Bool,
        profilePhotoProvider: (any ProfilePhotoImageProviding)? = nil,
        onIntroComplete: @escaping () -> Void = {}
    ) {
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.partnerDisplayName = partnerDisplayName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.playsIntro = playsIntro
        self.onIntroComplete = onIntroComplete
        self.profilePhotoProvider = profilePhotoProvider
            ?? (try? ProfilePhotoImageService.live())
            ?? UnavailableProfilePhotoImageProvider()
    }

    private var currentName: String {
        currentDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationYouName)
    }

    private var partnerName: String {
        partnerDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationPartnerName)
    }

    private var profilePhotoLoadID: String {
        [
            currentProfilePhotoAssetID?.uuidString ?? "none",
            partnerProfilePhotoAssetID?.uuidString ?? "none"
        ].joined(separator: "|")
    }

    var body: some View {
        GeometryReader { proxy in
            let heartCenter = CGPoint(
                x: proxy.size.width / 2,
                y: proxy.size.height * PairingCelebrationTiming.centerYRatio
            )
            let slotTarget = partnerSlot == .zero
                ? heartCenter
                : CGPoint(x: partnerSlot.midX, y: partnerSlot.midY)

            ZStack {
                core(heartCenter: heartCenter)

                PairingCelebrationProfilesView(
                    currentName: currentName,
                    currentPhotoData: currentProfilePhotoData,
                    partnerName: partnerName,
                    partnerPhotoData: partnerProfilePhotoData,
                    partnerSlotIsPlaceholder: introMode != .settled,
                    surroundingsOpacity: surroundingsShown ? 1 : 0,
                    slotCoordinateSpace: Self.coordinateSpace,
                    onPartnerSlotChange: { partnerSlot = $0 }
                )
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.5)

                partnerHero(heartCenter: heartCenter, slotTarget: slotTarget)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(.named(Self.coordinateSpace))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: start)
        .onChange(of: profilePhotoLoadID) { _, _ in
            startProfilePhotoPreloads()
        }
        .onDisappear {
            driver?.cancel()
            driver = nil
            currentProfilePhotoLoadTask?.cancel()
            currentProfilePhotoLoadTask = nil
            partnerProfilePhotoLoadTask?.cancel()
            partnerProfilePhotoLoadTask = nil
        }
    }

    @ViewBuilder
    private func core(heartCenter: CGPoint) -> some View {
        if introMode == .playing && phase <= .exploding {
            PairingCelebrationParticleField(start: animationStart)
                .opacity(phase >= .linking ? 0 : 1)
                .animation(PaeoniaMotion.meaningfulMoment, value: phase)
                .accessibilityHidden(true)

            PairingCelebrationHeartCore()
                .scaleEffect(heartScale)
                .opacity(heartOpacity)
                .shadow(color: .paeoniaAccentPrimary.opacity(0.65), radius: heartGlow)
                .position(x: heartCenter.x, y: heartCenter.y)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func partnerHero(heartCenter: CGPoint, slotTarget: CGPoint) -> some View {
        if introMode == .playing && partnerRevealed {
            PairingCelebrationAvatar(
                name: partnerName,
                tint: .paeoniaPartnerTwo,
                imageData: partnerProfilePhotoData
            )
                .scaleEffect(partnerScale)
                .shadow(color: .paeoniaPartnerTwo.opacity(0.55), radius: partnerGlow)
                .opacity(partnerOpacity)
                .position(partnerLanded ? slotTarget : heartCenter)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Sequence

    @MainActor
    private func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        startProfilePhotoPreloads()

        let animates = playsIntro && !reduceMotion

        // No intro: either the app launched straight into the paired space, or
        // Reduce Motion is on. Show the final, settled state immediately, with a
        // light success haptic when the moment is a real, fresh link.
        guard animates else {
            settleImmediately()
            if playsIntro {
                PaeoniaHaptics.pairedSuccessfully()
            }
            onIntroComplete()
            return
        }

        // Claim the intro up front so a SwiftUI view re-creation cannot replay it.
        // The animation below runs from this view's own state, not the prop.
        onIntroComplete()
        introMode = .playing
        resetForIntro()

        driver = Task { @MainActor in
            await runIntro()
        }
    }

    @MainActor
    private func settleImmediately() {
        introMode = .settled
        phase = .settled
        heartOpacity = 0
        partnerRevealed = false
        surroundingsShown = true
    }

    @MainActor
    private func resetForIntro() {
        animationStart = Date()
        phase = .heartAppearing
        heartScale = 0.2
        heartOpacity = 0
        heartGlow = 12
        partnerRevealed = false
        partnerOpacity = 0
        partnerScale = 0.5
        partnerLanded = false
        partnerGlow = 24
        surroundingsShown = false
    }

    @MainActor
    private func runIntro() async {
        revealHeart()
        guard await sleep(PairingCelebrationTiming.heartAppear) else { return }

        guard await absorbParticles() else { return }
        await waitForPartnerProfilePhotoPreload(maxSeconds: PairingCelebrationTiming.profilePhotoRevealGrace)

        revealPartner()
        guard await sleep(PairingCelebrationTiming.partnerHold) else { return }

        linkPartner()
        guard await sleep(PairingCelebrationTiming.landingSettle) else { return }

        phase = .settled
    }

    /// 1. The heart forms in the middle of the screen.
    @MainActor
    private func revealHeart() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            heartScale = 1
            heartOpacity = 1
        }
    }

    /// 2 + 3. Particles are pulled inward while haptic pressure accumulates.
    /// Returns `false` if the sequence was cancelled before the climax.
    @MainActor
    private func absorbParticles() async -> Bool {
        phase = .absorbing
        withAnimation(.easeInOut(duration: PairingCelebrationTiming.absorb)) {
            heartScale = 0.8
            heartGlow = 32
        }

        let haptics = Task { @MainActor in
            await buildHapticPressure()
        }
        let reachedClimax = await sleep(PairingCelebrationTiming.absorb)
        haptics.cancel()
        return reachedClimax
    }

    /// 4. The core bursts outward and reveals the partner's avatar at the center.
    @MainActor
    private func revealPartner() {
        phase = .exploding
        PaeoniaHaptics.pairingLinkExplosion()
        withAnimation(.easeOut(duration: 0.22)) {
            heartScale = 1.7
            heartOpacity = 0
        }

        partnerRevealed = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.03)) {
            partnerScale = heroScale
            partnerOpacity = 1
        }
    }

    /// 5. The partner glides into place and the rest of the linked state settles in.
    @MainActor
    private func linkPartner() {
        phase = .linking
        PaeoniaHaptics.streakContinued()
        withAnimation(.spring(response: 0.82, dampingFraction: 0.84)) {
            partnerScale = 1
            partnerLanded = true
            partnerGlow = 7
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.86).delay(0.16)) {
            surroundingsShown = true
        }
    }

    /// Builds soft impact pulses that rise in intensity while their gaps shrink,
    /// so the moment before the burst feels like pressure accumulating.
    @MainActor
    private func buildHapticPressure() async {
        let pulses: [(intensity: CGFloat, gap: Double)] = [
            (0.20, 0.34),
            (0.32, 0.30),
            (0.46, 0.26),
            (0.60, 0.21),
            (0.76, 0.16),
            (0.92, 0.12)
        ]

        for pulse in pulses {
            guard !Task.isCancelled else {
                return
            }

            PaeoniaHaptics.pairingLinkBuildUp(intensity: pulse.intensity)
            try? await Task.sleep(for: .seconds(pulse.gap))
        }
    }

    /// Sleeps for `seconds`, returning `false` if the sequence was cancelled.
    private func sleep(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    @MainActor
    private func startProfilePhotoPreloads() {
        currentProfilePhotoLoadTask?.cancel()
        partnerProfilePhotoLoadTask?.cancel()

        currentProfilePhotoData = nil
        partnerProfilePhotoData = nil
        currentProfilePhotoLoadFinished = currentProfilePhotoAssetID == nil
        partnerProfilePhotoLoadFinished = partnerProfilePhotoAssetID == nil

        let currentAssetID = currentProfilePhotoAssetID
        let partnerAssetID = partnerProfilePhotoAssetID

        partnerProfilePhotoLoadTask = Task { @MainActor in
            let data = await loadProfilePhotoData(for: partnerAssetID)
            guard !Task.isCancelled else {
                return
            }

            partnerProfilePhotoData = data
            partnerProfilePhotoLoadFinished = true
        }

        currentProfilePhotoLoadTask = Task { @MainActor in
            let data = await loadProfilePhotoData(for: currentAssetID)
            guard !Task.isCancelled else {
                return
            }

            currentProfilePhotoData = data
            currentProfilePhotoLoadFinished = true
        }
    }

    @MainActor
    private func loadProfilePhotoData(for mediaAssetID: UUID?) async -> Data? {
        await profilePhotoProvider.profilePhotoData(for: mediaAssetID)
    }

    @MainActor
    private func waitForPartnerProfilePhotoPreload(maxSeconds: Double) async {
        guard partnerProfilePhotoAssetID != nil,
              !partnerProfilePhotoLoadFinished,
              partnerProfilePhotoData == nil else {
            return
        }

        let deadline = Date().addingTimeInterval(maxSeconds)
        while !partnerProfilePhotoLoadFinished && Date() < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
}

/// Whether the celebration is still deciding, playing its intro, or showing the
/// final state directly. The undecided start avoids a one-frame flash of the
/// settled layout before `onAppear` runs.
private enum IntroMode {
    case undecided
    case playing
    case settled
}

/// The explicit beats of the celebration, used both to gate what is on screen and
/// to keep the particle field in step with the haptics and reveals.
enum PairingCelebrationPhase: Int, Comparable {
    case heartAppearing
    case absorbing
    case exploding
    case linking
    case settled

    static func < (lhs: PairingCelebrationPhase, rhs: PairingCelebrationPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Single source of truth for the celebration's timing so the time-driven
/// particle `Canvas` and the state-driven reveals never drift apart.
enum PairingCelebrationTiming {
    static let centerYRatio: CGFloat = 0.46

    static let heartAppear: Double = 0.55
    static let absorb: Double = 1.45
    static let explode: Double = 0.6
    static let partnerHold: Double = 0.9
    static let landingSettle: Double = 0.6
    static let profilePhotoRevealGrace: Double = 0.35

    /// Seconds from the animation start at which absorbing begins.
    static var absorbStart: Double { heartAppear }
    /// Seconds from the animation start at which the burst begins.
    static var explodeStart: Double { heartAppear + absorb }
    /// Seconds from the animation start after which no particles are drawn.
    static var explodeEnd: Double { explodeStart + explode }
}

private struct UnavailableProfilePhotoImageProvider: ProfilePhotoImageProviding {
    func profilePhotoData(for mediaAssetID: UUID?) async -> Data? {
        await Task.yield()
        return nil
    }
}

#Preview("Intro") {
    PairingCelebrationView(
        currentDisplayName: "Hjalmar Karlsen",
        partnerDisplayName: "Oda Larsen",
        playsIntro: true
    )
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .padding(.top, PaeoniaSpacing.screenTopSpacing)
    .padding(.bottom, PaeoniaSpacing.space16)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Settled") {
    PairingCelebrationView(
        currentDisplayName: "Hjalmar Karlsen",
        partnerDisplayName: "Oda Larsen",
        playsIntro: false
    )
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .padding(.top, PaeoniaSpacing.screenTopSpacing)
    .padding(.bottom, PaeoniaSpacing.space16)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}

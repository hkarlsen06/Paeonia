import Foundation
import SwiftUI

/// The cinematic moment shown the instant two people become linked.
///
/// The whole intro plays only when `playsIntro` is true and Reduce Motion is off.
/// Otherwise the final, settled state is shown immediately so the screen never
/// looks broken and the moment is never replayed on an ordinary app open.
///
/// A tap anywhere, or the VoiceOver "Skip animation" action, ends the intro early.
/// When the partner's name is not known yet, the intro waits for it for a moment.
/// `PairingCelebrationTimeline` runs the script; this view renders its state.
struct PairingCelebrationView: View {
    private static let coordinateSpace = "pairingCelebration"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var timeline: PairingCelebrationTimeline
    @State private var currentPhoto = PairingProfilePhoto()
    @State private var partnerPhoto: PairingProfilePhoto
    @State private var partnerSlot: CGRect = .zero

    let currentDisplayName: String?
    let currentProfilePhotoAssetID: UUID?
    let partnerDisplayName: String?
    let partnerProfilePhotoAssetID: UUID?
    let playsIntro: Bool
    /// The last button. It names the partner's gift when one is waiting.
    let dismissTitle: LocalizedStringResource
    let onIntroComplete: () -> Void
    let onDismiss: () -> Void
    private let profilePhotoProvider: (any ProfilePhotoImageProviding)?

    init(
        currentDisplayName: String?,
        currentProfilePhotoAssetID: UUID? = nil,
        partnerDisplayName: String? = nil,
        partnerProfilePhotoAssetID: UUID? = nil,
        playsIntro: Bool,
        dismissTitle: LocalizedStringResource = .pairingCelebrationGetStartedButton,
        profilePhotoProvider: (any ProfilePhotoImageProviding)? = nil,
        onIntroComplete: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.currentDisplayName = currentDisplayName
        self.currentProfilePhotoAssetID = currentProfilePhotoAssetID
        self.partnerDisplayName = partnerDisplayName
        self.partnerProfilePhotoAssetID = partnerProfilePhotoAssetID
        self.playsIntro = playsIntro
        self.dismissTitle = dismissTitle
        self.onIntroComplete = onIntroComplete
        self.onDismiss = onDismiss
        self.profilePhotoProvider = profilePhotoProvider ?? ProfilePhotoImageProviderFactory.shared

        // The timeline waits on the partner's photo, so both objects are made
        // here and the timeline reads the photo's loading state through a closure.
        let partnerPhoto = PairingProfilePhoto()
        _partnerPhoto = State(initialValue: partnerPhoto)
        _timeline = State(
            initialValue: PairingCelebrationTimeline(isPartnerPhotoLoading: { partnerPhoto.isLoading })
        )
    }

    private var currentName: String {
        currentDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationYouName)
    }

    private var partnerName: String {
        partnerDisplayName?.trimmedNonEmpty ?? String(localized: .pairingCelebrationPartnerName)
    }

    private var hasPartnerName: Bool {
        partnerDisplayName?.trimmedNonEmpty != nil
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
                stage(size: proxy.size, heartCenter: heartCenter, slotTarget: slotTarget)

                dismissButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(.named(Self.coordinateSpace))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            timeline.begin(
                playsIntro: playsIntro,
                reduceMotion: reduceMotion,
                partnerNameKnown: hasPartnerName,
                onIntroComplete: onIntroComplete
            )
        }
        .onChange(of: partnerDisplayName?.trimmedNonEmpty) { _, name in
            if name != nil {
                timeline.partnerNameDidArrive()
            }
        }
        .onChange(of: timeline.isSettled) { _, isSettled in
            if isSettled {
                AccessibilityNotification.Announcement(connectedText).post()
            }
        }
        .task(id: currentProfilePhotoAssetID) {
            await currentPhoto.load(assetID: currentProfilePhotoAssetID, provider: profilePhotoProvider)
        }
        .task(id: partnerProfilePhotoAssetID) {
            await partnerPhoto.load(assetID: partnerProfilePhotoAssetID, provider: profilePhotoProvider)
        }
        .onDisappear {
            timeline.stop()
        }
    }

    private var connectedText: String {
        String(localized: .pairingCelebrationConnectedAnnouncement(partnerName))
    }

    /// Everything except the button. VoiceOver reads it as one element, and a tap
    /// on it ends the intro early.
    private func stage(size: CGSize, heartCenter: CGPoint, slotTarget: CGPoint) -> some View {
        // The button trait applies only while a tap still does something, which
        // the rule cannot see.
        // swiftlint:disable:next accessibility_trait_for_button
        ZStack {
            core

            PairingCelebrationProfilesView(
                currentName: currentName,
                currentPhoto: currentPhoto.image,
                partnerName: partnerName,
                partnerPhoto: partnerPhoto.image,
                partnerSlotIsPlaceholder: timeline.mode != .settled,
                surroundingsOpacity: timeline.surroundingsShown ? 1 : 0,
                slotCoordinateSpace: Self.coordinateSpace,
                onPartnerSlotChange: { partnerSlot = $0 }
            )
            .position(x: size.width / 2, y: size.height * 0.5)

            partnerHero(heartCenter: heartCenter, slotTarget: slotTarget)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            timeline.skip()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(connectedText))
        .accessibilityAddTraits(timeline.canSkip ? .isButton : [])
        .accessibilityActions {
            if timeline.canSkip {
                Button {
                    timeline.skip()
                } label: {
                    Text(.pairingCelebrationSkipAnimationAction)
                }
            }
        }
    }

    @ViewBuilder
    private var core: some View {
        if timeline.showsHeart {
            PairingCelebrationParticleField(
                playback: timeline.particlePlayback,
                showsParticles: timeline.showsParticles
            )
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func partnerHero(heartCenter: CGPoint, slotTarget: CGPoint) -> some View {
        if timeline.mode == .playing && timeline.partnerRevealed {
            PairingCelebrationAvatar(
                name: partnerName,
                tint: .paeoniaPartnerTwo,
                image: partnerPhoto.image
            )
            .scaleEffect(timeline.partnerScale)
            .shadow(color: .paeoniaPartnerTwo.opacity(0.55), radius: timeline.partnerGlow)
            .opacity(timeline.partnerOpacity)
            .position(timeline.partnerLanded ? slotTarget : heartCenter)
            .accessibilityHidden(true)
        }
    }

    private var dismissButton: some View {
        let isVisible = timeline.dismissButtonShown

        return VStack {
            Spacer()

            Button(action: dismiss) {
                Text(dismissTitle)
                    .contentTransition(.opacity)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            // The gift can finish loading after the button is up.
            .animation(PaeoniaMotion.stateChange, value: String(localized: dismissTitle))
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 18)
            .allowsHitTesting(isVisible)
            .disabled(!isVisible)
            .accessibilityHidden(!isVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dismiss() {
        PaeoniaHaptics.pairingCelebrationDismissed()
        onDismiss()
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

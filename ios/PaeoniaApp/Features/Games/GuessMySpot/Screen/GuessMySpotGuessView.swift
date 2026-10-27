import MapKit
import SwiftUI

/// The partner's photo on top, a tap away from full screen, and the whole world under it.
/// A tap drops the guess pin, the next tap moves it, and "Lock in my guess"
/// sends it.
struct GuessMySpotGuessView: View {
    @Bindable var viewModel: GuessMySpotViewModel

    @State private var camera = GuessMySpotCamera.world
    @AppStorage(GuessMySpotMap.satelliteKey) private var satellite = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GuessMySpotSplitLayout {
            liveRow
        } photo: {
            GuessMySpotPhotoPane(
                image: viewModel.roundPhoto,
                preview: viewModel.roundPhotoPreview,
                failed: viewModel.roundPhotoFailed,
                retry: viewModel.retryRoundPhoto
            )
        } map: {
            GuessMySpotMap(
                position: $camera,
                pins: pins,
                onTap: { spot in
                    withAnimation(reduceMotion ? nil : PaeoniaMotion.cardReveal) {
                        viewModel.dropGuess(at: spot)
                    }
                },
                onCameraChange: { viewModel.guessMapMoved(to: $0.rect, settled: true) },
                onCameraMove: { viewModel.guessMapMoved(to: $0.rect, settled: false) },
                accessibilityValue: viewModel.guessPin == nil ? .guessMySpotMapNoPin : .guessMySpotMapPinDropped
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewModel.guessMapFrame = $0 }
            .overlay(alignment: .bottom) {
                if viewModel.guessPin == nil {
                    Text(.guessMySpotGuessHint)
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaTextPrimary)
                        .padding(.horizontal, PaeoniaSpacing.space12)
                        .padding(.vertical, PaeoniaSpacing.space8)
                        .glassEffect(.regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.6)), in: Capsule())
                        .padding(PaeoniaSpacing.space12)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .animation(PaeoniaMotion.stateChange, value: viewModel.guessPin == nil)
        } footer: {
            EmptyView()
        } bottom: {
            lockButton
        }
        .gameInviteToolbar(
            invite: viewModel.invite,
            partnerName: viewModel.partnerName,
            send: viewModel.sendInvite,
            identifier: "guessMySpot.invite"
        )
        .onChange(of: satellite, initial: true) { _, satellite in
            viewModel.guessMapSatelliteChanged(to: satellite)
        }
        .accessibilityIdentifier("guessMySpot.guess")
    }

    private var pins: [GuessMySpotMap.Pin] {
        guard let guess = viewModel.guessPin else { return [] }
        return [GuessMySpotMap.Pin(id: "guess", coordinate: guess, style: viewModel.myStyle)]
    }

    private var liveRow: some View {
        GameLiveRow {
            let isHere = viewModel.partnerStatus != .away
            let name = viewModel.partnerName
            GamePresenceLabel(
                player: viewModel.partner,
                text: isHere ? .guessMySpotGuessWatching(name) : .guessMySpotGuessLater(name),
                isHere: isHere,
                showsRing: isHere
            )
            .animation(PaeoniaMotion.stateChange, value: isHere)
        } trailing: {
            EmptyView()
        }
    }

    private var lockButton: some View {
        Button {
            if viewModel.lockGuess() {
                PaeoniaHaptics.drawingSent()
                GameSound.send.play()
            } else {
                PaeoniaHaptics.validationError()
            }
        } label: {
            Label {
                Text(.guessMySpotGuessLock)
            } icon: {
                Image(systemName: "lock.fill").accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(viewModel.guessPin == nil)
        .accessibilityIdentifier("guessMySpot.guess.lock")
    }
}

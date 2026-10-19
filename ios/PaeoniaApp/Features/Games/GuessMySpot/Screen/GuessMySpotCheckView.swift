import MapKit
import SwiftUI

/// The picked photo over the map with its spot. A tap moves the pin. "Send to
/// [Name]" sends it, and back goes to the camera roll without sending.
struct GuessMySpotCheckView: View {
    @Bindable var viewModel: GuessMySpotViewModel

    @State private var camera = GuessMySpotCamera.world
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var draft: GuessMySpotDraft? { viewModel.draft }

    var body: some View {
        GuessMySpotSplitLayout {
            EmptyView()
        } photo: {
            GuessMySpotPhotoPane(image: draft?.image)
        } map: {
            GuessMySpotMap(
                position: $camera,
                pins: pins,
                onTap: { spot in
                    withAnimation(reduceMotion ? nil : PaeoniaMotion.cardReveal) {
                        viewModel.movePin(to: spot)
                    }
                },
                accessibilityValue: draft?.spot == nil ? .guessMySpotMapNoPin : .guessMySpotMapPinDropped
            )
        } footer: {
            footer
        } bottom: {
            sendButton
        }
        .onChange(of: draft?.roundID, initial: true) { _, _ in
            // A new photo: its spot, or else near home, or else the whole world.
            if let spot = draft?.spot {
                camera = GuessMySpotCamera.around(spot, meters: 2_000)
            } else if let area = viewModel.draftStartArea {
                camera = GuessMySpotCamera.around(area.center, meters: area.meters)
            } else {
                camera = GuessMySpotCamera.world
            }
        }
        .accessibilityIdentifier("guessMySpot.check")
    }

    private var pins: [GuessMySpotMap.Pin] {
        guard let spot = draft?.spot else { return [] }
        return [GuessMySpotMap.Pin(id: "mine", coordinate: spot, style: viewModel.myStyle)]
    }

    private var footer: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(draft?.spot != nil ? .guessMySpotCheckFoundTitle : .guessMySpotCheckMissingTitle)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(hint)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
            if let name = draft?.placeName, draft?.spot != nil {
                Label {
                    Text(verbatim: name)
                } icon: {
                    Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
                }
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .transition(.opacity)
                .accessibilityIdentifier("guessMySpot.check.place")
            }
            Text(.guessMySpotCheckPrivate(viewModel.partnerName))
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .padding(.top, PaeoniaSpacing.space4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .animation(PaeoniaMotion.stateChange, value: draft?.placeName)
    }

    private var hint: LocalizedStringResource {
        if draft?.spotFromPhoto == true { return .guessMySpotCheckFoundHint }
        return draft?.spot == nil ? .guessMySpotCheckMissingHint : .guessMySpotCheckMovedHint
    }

    private var sendButton: some View {
        Button {
            if viewModel.send() {
                PaeoniaHaptics.drawingSent()
                GameSound.send.play()
            } else {
                PaeoniaHaptics.validationError()
            }
        } label: {
            Label {
                Text(.guessMySpotCheckSend(viewModel.partnerName))
            } icon: {
                Image(systemName: "paperplane.fill").accessibilityHidden(true)
            }
        }
        .buttonStyle(PaeoniaPrimaryButtonStyle())
        .disabled(!viewModel.canSend)
        .accessibilityIdentifier("guessMySpot.check.send")
    }
}

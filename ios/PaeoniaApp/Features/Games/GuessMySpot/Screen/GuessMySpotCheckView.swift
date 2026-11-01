import MapKit
import SwiftUI

/// The picked photo over the map with its spot. A tap moves the pin. "Send to
/// [Name]" sends it, and back goes to the camera roll without sending.
struct GuessMySpotCheckView: View {
    @Bindable var viewModel: GuessMySpotViewModel

    @State private var camera: MapCameraPosition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(viewModel: GuessMySpotViewModel) {
        _viewModel = Bindable(viewModel)
        // Starts on the spot, so the map doesn't open on the world and then jump.
        _camera = State(initialValue: Self.startCamera(for: viewModel))
    }

    private var draft: GuessMySpotDraft? { viewModel.draft }

    var body: some View {
        GuessMySpotSplitLayout {
            EmptyView()
        } photo: {
            GuessMySpotPhotoPane(image: draft?.image, accessibilityText: draft?.accessibilityText)
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
            .overlay(alignment: .bottom) {
                if draft?.spot == nil {
                    GuessMySpotMapHint(text: .guessMySpotCheckMissingHint)
                        .transition(.opacity)
                }
            }
            .animation(PaeoniaMotion.stateChange, value: draft?.spot == nil)
        } footer: {
            footer
        } bottom: {
            sendButton
        }
        .onChange(of: draft?.roundID) { _, _ in
            camera = Self.startCamera(for: viewModel)
        }
    }

    /// A new photo: its spot, or else near home, or else the whole world.
    private static func startCamera(for viewModel: GuessMySpotViewModel) -> MapCameraPosition {
        if let spot = viewModel.draft?.spot {
            return GuessMySpotCamera.around(spot, meters: 2_000)
        } else if let area = viewModel.draftStartArea {
            return GuessMySpotCamera.around(area.center, meters: area.meters)
        }
        return GuessMySpotCamera.world
    }

    private var pins: [GuessMySpotMap.Pin] {
        guard let spot = draft?.spot else { return [] }
        return [GuessMySpotMap.Pin(id: "mine", coordinate: spot, style: viewModel.myStyle)]
    }

    /// Every line keeps its height whatever the pin is doing, so the map never
    /// moves when the place name comes in or goes while it's looked up again.
    private var footer: some View {
        VStack(spacing: PaeoniaSpacing.space4) {
            Text(draft?.spot != nil ? .guessMySpotCheckFoundTitle : .guessMySpotCheckMissingTitle)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .accessibilityAddTraits(.isHeader)
            placeLine
            GuessMySpotPhotoDescriptionEditor(viewModel: viewModel)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var placeLine: some View {
        let name = draft?.spot == nil ? nil : draft?.placeName
        return Label {
            // A space holds the line's height while there is no name.
            Text(verbatim: name ?? " ")
        } icon: {
            Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
        }
        .font(PaeoniaTypography.bodyEmphasis)
        .foregroundStyle(.paeoniaTextPrimary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .opacity(name == nil ? 0 : 1)
        .animation(PaeoniaMotion.stateChange, value: name)
        .accessibilityHidden(name == nil)
        .accessibilityIdentifier("guessMySpot.check.place")
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

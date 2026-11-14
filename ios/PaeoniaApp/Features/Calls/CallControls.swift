import SwiftUI

/// The row of round buttons at the bottom of the call screen: mute, speaker (or the system's
/// picker with AirPods or a car), camera, flip while your camera is on, and end.
struct CallControls: View {
    let session: CallSession
    let engine: any CallEngineActions

    var body: some View {
        // Each button takes an equal share, so five fit on the smallest phone.
        HStack(alignment: .top, spacing: 0) {
            CallControlButton(
                systemImage: session.isMuted ? "mic.slash.fill" : "mic.fill",
                title: .callsControlMute, isOn: session.isMuted, identifier: "calls.mute"
            ) { engine.setMuted(!session.isMuted) }

            speaker

            CallControlButton(
                systemImage: session.isCameraOn ? "video.fill" : "video.slash.fill",
                title: .callsControlCamera, isOn: session.isCameraOn, identifier: "calls.camera"
            ) { engine.setCameraOn(!session.isCameraOn) }

            if session.isCameraOn {
                CallControlButton(
                    systemImage: "arrow.triangle.2.circlepath.camera.fill",
                    title: .callsControlFlip, identifier: "calls.flip"
                ) { engine.flipCamera() }
                .transition(.scale.combined(with: .opacity))
            }

            CallControlButton(
                systemImage: "phone.down.fill", title: .callsControlEnd, fill: .paeoniaError, identifier: "calls.end"
            ) { engine.end() }
        }
    }

    @ViewBuilder
    private var speaker: some View {
        if case let .external(name) = session.audioRoute {
            VStack(spacing: PaeoniaSpacing.space8) {
                CallRoutePicker()
                    .frame(width: CallControlButton.size, height: CallControlButton.size)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel(Text(.callsControlAudioRoute(name)))
                    .accessibilityIdentifier("calls.route")
                Text(verbatim: name)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: CallControlButton.size + PaeoniaSpacing.space12)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        } else {
            CallControlButton(
                systemImage: "speaker.wave.2.fill", title: .callsControlSpeaker,
                isOn: session.audioRoute == .speaker, identifier: "calls.speaker"
            ) { engine.toggleSpeaker() }
        }
    }
}

/// A round call button with its name under it. A switch that is on turns white.
struct CallControlButton: View {
    static let size: CGFloat = 60

    let systemImage: String
    let title: LocalizedStringResource
    var isOn: Bool?
    var fill: Color?
    let identifier: String
    let action: () -> Void

    init(
        systemImage: String, title: LocalizedStringResource, isOn: Bool? = nil, fill: Color? = nil,
        identifier: String, action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.isOn = isOn
        self.fill = fill
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: PaeoniaSpacing.space8) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isOn == true ? Color.paeoniaTextInverse : Color.paeoniaTextPrimary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.size, height: Self.size)
                    .background { background }
                Text(title)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isOn == true ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var background: some View {
        if let fill {
            Circle().fill(fill)
        } else if isOn == true {
            Circle().fill(Color.paeoniaTextPrimary)
        } else {
            Circle().fill(.clear).glassEffect(.regular.interactive(), in: Circle())
        }
    }
}

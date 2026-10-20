import SwiftUI

/// The settled reveal's shortcuts in one capsule in the map's top leading corner,
/// as the satellite button sits in its trailing one: to your pin, out to both pins,
/// and to your partner's pin. The one for what the map shows now is off.
struct GuessMySpotRevealCameraButtons: View {
    enum Focus { case mine, both, partner }

    let myStyle: BoardPieceStyle
    let partnerStyle: BoardPieceStyle
    let partnerName: String
    /// What the map shows now. Nil once the map was moved by hand.
    let focus: Focus?
    let onSelect: (Focus) -> Void

    var body: some View {
        HStack(spacing: 0) {
            button(.mine, label: .guessMySpotRevealCameraMine) { mark(myStyle) }
            button(.both, label: .guessMySpotRevealCameraBoth) {
                Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityHidden(true)
            }
            button(.partner, label: .guessMySpotRevealCameraPartner(partnerName)) { mark(partnerStyle) }
        }
        .padding(.horizontal, PaeoniaSpacing.space4)
        .glassEffect(.regular.tint(Color.paeoniaBackgroundSecondary.opacity(0.6)), in: Capsule())
        .padding(PaeoniaSpacing.space8)
        .animation(PaeoniaMotion.stateChange, value: focus)
    }

    private func button(
        _ target: Focus,
        label: LocalizedStringResource,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        let isCurrent = focus == target
        return Button {
            PaeoniaHaptics.selection()
            GameSound.tap.play(volume: 0.5)
            onSelect(target)
        } label: {
            icon()
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isCurrent ? 0.35 : 1)
        .disabled(isCurrent)
        .accessibilityLabel(Text(label))
    }

    /// A small copy of the pin's head.
    private func mark(_ style: BoardPieceStyle) -> some View {
        ZStack {
            Circle()
                .fill(style.color)
            Circle()
                .strokeBorder(.paeoniaTextPrimary.opacity(0.85), lineWidth: 1.5)
            BoardMarkView(style: style, tint: .paeoniaTextInverse)
                .padding(5)
        }
        .frame(width: 26, height: 26)
    }
}

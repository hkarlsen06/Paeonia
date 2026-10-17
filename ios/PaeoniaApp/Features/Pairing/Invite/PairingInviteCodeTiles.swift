import SwiftUI

/// The invite code as six tiles with its label and expiry line. VoiceOver reads the
/// tiles as one element that spells the code out.
struct PairingInviteCodeBlock: View {
    let invite: PairingInvite

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.pairingInviteCodeLabel)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)

            let characters = Array(invite.code)
            PairingCodeCellLayout { index in
                if index < characters.count {
                    PairingInviteCodeCharacterTile(
                        character: characters[index],
                        inviteID: invite.id,
                        index: index
                    )
                    .id("\(invite.id)-\(index)")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(.pairingInviteCodeLabel))
            .accessibilityValue(Text(invite.code).speechSpellsOutCharacters())

            HStack(spacing: PaeoniaSpacing.space4) {
                Text(.pairingInviteExpiresLabel)
                Text(invite.expiresAt, format: .dateTime.month().day().hour().minute())
            }
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextTertiary)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct PairingInviteCodeCharacterTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var inviteCodeTileHeight: CGFloat = 58
    @State private var isSettled = false

    let character: Character
    let inviteID: UUID
    let index: Int

    var body: some View {
        Text(String(character))
            .font(.system(.title2, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.paeoniaTextPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: inviteCodeTileHeight)
            .background(.paeoniaBackgroundElevated)
            .clipShape(RoundedRectangle(cornerRadius: PaeoniaRadius.radius12, style: .continuous))
            .scaleEffect(isSettled ? 1 : 0.72)
            .offset(y: isSettled ? 0 : 12)
            .opacity(isSettled ? 1 : 0)
            .onAppear(perform: bounceIntoPlace)
            .onChange(of: inviteID) { _, _ in
                isSettled = false
                bounceIntoPlace()
            }
    }

    private func bounceIntoPlace() {
        guard !reduceMotion else {
            isSettled = true
            return
        }

        let delay = Double(index) * 0.035
        withAnimation(
            .spring(response: 0.42, dampingFraction: 0.58)
            .delay(delay)
        ) {
            isSettled = true
        }
        // A quiet click as each tile lands, so the six make a short run.
        Task {
            try? await Task.sleep(for: .seconds(delay + 0.12))
            GameSound.tick.play(volume: 0.3)
        }
    }
}

/// A quiet line under the code. The app moves on by itself when the partner joins, so
/// there is nothing to tap. With notifications allowed it promises a notification
/// instead. The dot pulses, and stays still with Reduce Motion on.
struct PairingInviteWaitingLine: View {
    var notifiesOnJoin = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Circle()
                .fill(.paeoniaAccentPrimary)
                .frame(width: PaeoniaSpacing.space8, height: PaeoniaSpacing.space8)
                .opacity(isDimmed ? 0.3 : 1)
                .accessibilityHidden(true)

            Text(notifiesOnJoin ? .pairingInviteWaitingNotified : .pairingInviteWaitingStatus)
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(PaeoniaMotion.stateChange, value: notifiesOnJoin)
        }
        .onAppear {
            guard !reduceMotion else {
                return
            }

            withAnimation(PaeoniaMotion.standardCurve(duration: 1.1).repeatForever(autoreverses: true)) {
                isDimmed = true
            }
        }
    }
}

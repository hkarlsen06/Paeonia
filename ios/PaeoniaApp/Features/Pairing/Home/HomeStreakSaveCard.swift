import SwiftUI

/// The Home card on a broken streak's free save day: both partners doing one small
/// thing today brings it back. It goes away at the end of the save day, when the
/// streak pill turns to the restore offer, or when this person closes it. Tapping it
/// opens the streak sheet.
struct HomeStreakSaveCard: View {
    let streak: StreakPillState
    var onTap: (() -> Void)?
    var onDismiss: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date.now

    var body: some View {
        let state = streak.resolved(at: now)
        Group {
            if state.isSavable {
                card(count: state.restorableCount)
                    .transition(.opacity)
            }
        }
        .task(id: streak.changeDates) { await followChangeDates() }
    }

    /// Looks again at each moment the streak changes without new data. The card fades out
    /// when the save day ends, and the Home cards under it glide up.
    private func followChangeDates() async {
        now = .now
        for date in streak.changeDates where date > now {
            try? await Task.sleep(for: .seconds(date.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : PaeoniaMotion.homeLayoutChange) { now = .now }
        }
    }

    private func card(count: Int) -> some View {
        PaeoniaCard {
            HStack(alignment: .top, spacing: 0) {
                Button {
                    onTap?()
                } label: {
                    message(count: count)
                }
                .buttonStyle(.plain)
                closeButton
            }
        }
    }

    /// A bare cross whose tap square reaches into the card's padding, so the text keeps
    /// most of the width. Outside the card's button, so VoiceOver reaches it on its own.
    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, -PaeoniaSpacing.space12)
        .padding(.trailing, -PaeoniaSpacing.space12)
        .accessibilityLabel(Text(.commonClose))
        .accessibilityIdentifier("home.streakSave.close")
    }

    private func message(count: Int) -> some View {
        HStack(alignment: .center, spacing: PaeoniaSpacing.space16) {
            FlameShape()
                .fill(
                    LinearGradient(
                        colors: [.paeoniaAccentPrimary, .paeoniaInkGold],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 24, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(.homeStreakSaveTitle(count))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(.homeStreakSaveMessage)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Save day") {
    HomeStreakSaveCard(
        streak: StreakPillState(
            count: 0,
            isRestorable: false,
            restorableCount: 18,
            isSavable: true,
            saveDeadline: .now.addingTimeInterval(6 * 3_600),
            restoreDeadline: .now.addingTimeInterval(54 * 3_600)
        )
    )
    .padding()
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif

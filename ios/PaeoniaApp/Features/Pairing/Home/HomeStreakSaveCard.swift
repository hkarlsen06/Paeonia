import SwiftUI

/// The Home card on a broken streak's free save day: both partners doing one small
/// thing today brings it back. It goes away at the end of the save day, when the
/// streak pill turns to the restore offer. Tapping it opens the streak sheet.
struct HomeStreakSaveCard: View {
    let streak: StreakPillState
    var onTap: (() -> Void)?

    var body: some View {
        TimelineView(.explicit(streak.changeDates)) { _ in
            let state = streak.resolved(at: .now)
            if state.isSavable {
                Button {
                    onTap?()
                } label: {
                    card(count: state.restorableCount)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
    }

    private func card(count: Int) -> some View {
        PaeoniaCard {
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
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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

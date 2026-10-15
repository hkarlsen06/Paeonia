import SwiftUI

/// The line under the board. On the left, "[Name] will see it later" while the
/// partner is away, or the game's own hint while it has one (Ludo's "Roll again").
/// Nothing shows while the partner is here, since the green dot on their avatar
/// says so. VoiceOver still hears both changes.
/// On the right, an "Another turn" chip that pops in each time the extra turn
/// count goes up and fades after 1.5 seconds. The chip's space is always
/// reserved, so nothing around the row moves when it shows.
struct BoardGameStatusRow: View {
    let partnerName: String
    let status: BoardGamePartnerStatus
    /// Goes up with each extra turn of mine (Dots and Boxes).
    let extraTurnCount: Int
    var hint: LocalizedStringResource?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The extra turn count the visible chip belongs to, or nil while no chip shows.
    @State private var shownTurn: Int?
    @State private var hideTask: Task<Void, Never>?

    /// How long the chip stays before it fades.
    static let chipDuration: TimeInterval = 1.5

    var body: some View {
        GameLiveRow {
            presence
        } trailing: {
            chipSlot
        }
        .animation(PaeoniaMotion.stateChange, value: status)
        .animation(PaeoniaMotion.stateChange, value: hint)
        .onChange(of: status) { _, newStatus in
            AccessibilityNotification.Announcement(String(localized: text(for: newStatus))).post()
        }
        .onChange(of: extraTurnCount) { old, new in
            if new > old {
                popChip(for: new)
            }
        }
        .onDisappear { hideTask?.cancel() }
    }

    // MARK: Presence

    @ViewBuilder
    private var presence: some View {
        if let hint {
            Text(hint)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .transition(.opacity)
                .accessibilityIdentifier("boardGames.hint")
        } else if status == .away {
            Text(text(for: status))
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
                .transition(.opacity)
                .accessibilityIdentifier("boardGames.status")
        }
    }

    private func text(for status: BoardGamePartnerStatus) -> LocalizedStringResource {
        switch status {
        case .here: .boardGamesStatusHere(partnerName)
        case .away: .boardGamesStatusLater(partnerName)
        }
    }

    // MARK: Another turn

    private var chip: some View {
        Text(.boardGamesStatusAnotherTurn)
            .font(PaeoniaTypography.caption.weight(.bold))
            .foregroundStyle(.paeoniaTextInverse)
            .padding(.horizontal, PaeoniaSpacing.space12)
            .padding(.vertical, PaeoniaSpacing.space4)
            .background(.paeoniaAccentPrimary, in: Capsule(style: .continuous))
    }

    /// An invisible chip holds the space. The visible one is drawn over it, and a
    /// new identity for each extra turn makes it pop in again.
    private var chipSlot: some View {
        chip
            .hidden()
            .overlay {
                if let shownTurn {
                    chip
                        .id(shownTurn)
                        .transition(chipTransition)
                }
            }
            .accessibilityHidden(true)
    }

    private var chipTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }

    private func popChip(for count: Int) {
        hideTask?.cancel()
        withAnimation(reduceMotion ? PaeoniaMotion.stateChange : PaeoniaMotion.cardReveal) {
            shownTurn = count
        }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.chipDuration))
            guard !Task.isCancelled else { return }
            withAnimation(PaeoniaMotion.stateChange) {
                shownTurn = nil
            }
        }
    }
}

/// A small green dot that dims and brightens slowly. Reduce Motion keeps it still.
struct BoardGamePresenceDot: View {
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDim = false

    var body: some View {
        Circle()
            .fill(.paeoniaSuccess)
            .frame(width: size, height: size)
            .opacity(isDim ? 0.45 : 1)
            .scaleEffect(isDim ? 0.85 : 1)
            .animation(pulse, value: isDim)
            .onAppear { isDim = !reduceMotion }
            .accessibilityHidden(true)
    }

    private var pulse: Animation? {
        reduceMotion ? nil : PaeoniaMotion.standardCurve(duration: 1.2).repeatForever(autoreverses: true)
    }
}

#if DEBUG
#Preview("Presence") {
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameStatusRow(partnerName: "Robin", status: .here, extraTurnCount: 0)
        BoardGameStatusRow(partnerName: "Robin", status: .away, extraTurnCount: 0)
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}

#Preview("Another turn") {
    @Previewable @State var count = 0
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameStatusRow(partnerName: "Robin", status: .here, extraTurnCount: count)
        Button { count += 1 } label: { Text(verbatim: "Extra turn") }
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif

import SwiftUI

/// A centered line under the board with the game's own hint while it has one
/// (Ludo's "Roll again"). Whether the partner is here shows elsewhere: the steady green ring
/// on their avatar, or `BoardGameAwayLine` under the bottom content. Both remain
/// readable without interrupting VoiceOver for changes in partner activity.
/// Without a hint, an "Another turn" chip that pops in each time the extra turn
/// count goes up and fades after 1.5 seconds. The chip's space is always
/// reserved, so nothing around the row moves when it shows.
struct BoardGameStatusRow: View {
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
            if hint == nil || extraTurnCount > 0 {
                chipSlot
            }
        }
        .animation(PaeoniaMotion.stateChange, value: hint)
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

/// "[Name] isn't here right now", under the bottom content while the partner is away.
/// The partner's avatar identifies their presence while they are here.
struct BoardGameAwayLine: View {
    let partnerName: String

    var body: some View {
        Text(.boardGamesStatusAway(partnerName))
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(.paeoniaTextTertiary)
            .multilineTextAlignment(.center)
            .transition(.opacity)
            .accessibilityIdentifier("boardGames.status")
    }
}

#if DEBUG
#Preview("Hint and presence") {
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameStatusRow(extraTurnCount: 0, hint: .boardGamesStatusAnotherTurn)
        BoardGameAwayLine(partnerName: "Robin")
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}

#Preview("Another turn") {
    @Previewable @State var count = 0
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameStatusRow(extraTurnCount: count)
        Button { count += 1 } label: { Text(verbatim: "Extra turn") }
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif

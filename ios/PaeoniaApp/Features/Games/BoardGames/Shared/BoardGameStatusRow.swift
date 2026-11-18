import SwiftUI

/// What the line under the board says, from the strongest claim down. A
/// finished game has no line, because the result panel says how it ended.
nonisolated enum BoardGameStatusLine: Equatable {
    /// The game's own hint, such as Ludo's "Roll again" or Ultimate
    /// Tic-Tac-Toe's "Choose a board".
    case hint(LocalizedStringResource)
    /// "Another turn" for a moment after I earned one. `count` is the extra
    /// turn it belongs to, so each new one pops in again.
    case anotherTurn(count: Int)
    case yourTurn
    case partnerTurn

    /// `anotherTurn` is the extra turn count whose "Another turn" still shows, or nil.
    init?(turn: BoardGameTurnLabel, hint: LocalizedStringResource?, anotherTurn: Int?) {
        switch turn {
        case .youWon, .partnerWon, .draw:
            return nil
        case .yourTurn, .partnerTurn:
            if let hint {
                self = .hint(hint)
            } else if let anotherTurn {
                self = .anotherTurn(count: anotherTurn)
            } else {
                self = turn == .yourTurn ? .yourTurn : .partnerTurn
            }
        }
    }

    var isAnotherTurn: Bool {
        if case .anotherTurn = self { true } else { false }
    }
}

/// The centered line under the board: "Your turn" or "[Name]'s turn" with a dot
/// in that player's color, the game's own hint while it has one, or "Another
/// turn" for 1.5 seconds each time the extra turn count goes up. The line
/// cross-fades when it changes. Its height is always held, so nothing around
/// the row moves when it changes or goes. Whether the partner is here shows
/// elsewhere: the floating avatar's game badge, or `BoardGameAwayLine` under
/// the bottom content.
struct BoardGameStatusRow: View {
    let turn: BoardGameTurnLabel
    let me: BoardGamePlayerInfo
    let partner: BoardGamePlayerInfo
    /// Goes up with each extra turn of mine (Dots and Boxes and Ludo).
    let extraTurnCount: Int
    var hint: LocalizedStringResource?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var dotSide: CGFloat = 8
    /// The extra turn count whose "Another turn" shows, or nil.
    @State private var anotherTurn: Int?
    @State private var hideTask: Task<Void, Never>?

    /// How long "Another turn" stays before the line goes back to "Your turn".
    static let anotherTurnDuration: TimeInterval = 1.5

    private var line: BoardGameStatusLine? {
        BoardGameStatusLine(turn: turn, hint: hint, anotherTurn: anotherTurn)
    }

    var body: some View {
        let line = self.line
        ZStack {
            label(.yourTurn)
                .hidden()
                .accessibilityHidden(true)
            if let line {
                label(line)
                    .id(line.id)
                    .transition(transition(for: line))
            }
        }
        .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.space24)
        .padding(.horizontal, PaeoniaSpacing.space8)
        .animation(animation(for: line), value: line)
        .onChange(of: extraTurnCount) { old, new in
            // A hint already says it, as Ludo's "Roll again" does.
            if new > old, hint == nil {
                showAnotherTurn(new)
            }
        }
        .onDisappear { hideTask?.cancel() }
    }

    private func label(_ line: BoardGameStatusLine) -> some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            Circle()
                .fill(turn == .partnerTurn ? partner.style.color : me.style.color)
                .frame(width: dotSide, height: dotSide)
                .accessibilityHidden(true)
            text(line)
                .font(PaeoniaTypography.caption.weight(line.isAnotherTurn ? .bold : .semibold))
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(line.identifier)
        }
    }

    private func text(_ line: BoardGameStatusLine) -> Text {
        switch line {
        case .hint(let hint): Text(hint)
        case .anotherTurn: Text(.boardGamesStatusAnotherTurn)
        case .yourTurn: Text(.boardGamesTurnYours)
        case .partnerTurn: Text(.boardGamesTurnPartner(partner.name))
        }
    }

    /// "Another turn" rises into place the way a new chip would. Every other
    /// change is a cross-fade.
    private func transition(for line: BoardGameStatusLine) -> AnyTransition {
        guard line.isAnotherTurn, !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }

    private func animation(for line: BoardGameStatusLine?) -> Animation {
        line?.isAnotherTurn == true && !reduceMotion ? PaeoniaMotion.cardReveal : PaeoniaMotion.stateChange
    }

    private func showAnotherTurn(_ count: Int) {
        hideTask?.cancel()
        anotherTurn = count
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.anotherTurnDuration))
            guard !Task.isCancelled else { return }
            anotherTurn = nil
        }
    }
}

extension BoardGameStatusLine {
    /// Tells one line from the next, so a change cross-fades instead of
    /// changing the text in place.
    fileprivate var id: String {
        switch self {
        case .hint(let hint): "hint.\(hint.key)"
        case .anotherTurn(let count): "anotherTurn.\(count)"
        case .yourTurn: "yourTurn"
        case .partnerTurn: "partnerTurn"
        }
    }

    fileprivate var identifier: String {
        if case .hint = self { "boardGames.hint" } else { "boardGames.turnLine" }
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
#Preview("Turns and hint") {
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameStatusRow(
            turn: .yourTurn, me: BoardGamePreviewData.me, partner: BoardGamePreviewData.partner, extraTurnCount: 0
        )
        BoardGameStatusRow(
            turn: .partnerTurn, me: BoardGamePreviewData.me, partner: BoardGamePreviewData.partner, extraTurnCount: 0
        )
        BoardGameStatusRow(
            turn: .yourTurn, me: BoardGamePreviewData.me, partner: BoardGamePreviewData.partner, extraTurnCount: 0,
            hint: .ultimateTicTacToeHintChooseBoard
        )
        BoardGameAwayLine(partnerName: "Robin")
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}

#Preview("Another turn") {
    @Previewable @State var count = 0
    @Previewable @State var turn = BoardGameTurnLabel.yourTurn
    VStack(spacing: PaeoniaSpacing.space24) {
        BoardGameStatusRow(
            turn: turn, me: BoardGamePreviewData.me, partner: BoardGamePreviewData.partner, extraTurnCount: count
        )
        Button { count += 1 } label: { Text(verbatim: "Extra turn") }
        Button { turn = turn == .yourTurn ? .partnerTurn : .yourTurn } label: { Text(verbatim: "Hand over") }
    }
    .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(.paeoniaBackgroundSecondary)
    .preferredColorScheme(.dark)
}
#endif

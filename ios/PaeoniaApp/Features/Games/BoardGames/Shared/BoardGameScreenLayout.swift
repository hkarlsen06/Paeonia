import SwiftUI

/// How big the board is, so a game never resizes it. The width decides, and the
/// wide layout also keeps the board on screen by height.
enum BoardGameMetrics {
    /// The board never grows past this on a phone or in a narrow window.
    static let maxBoard: CGFloat = 560
    /// The board never grows past this in the wide layout.
    static let maxWideBoard: CGFloat = 640
    /// The widest the column beside the board grows in the wide layout.
    static let sideColumnWidth: CGFloat = 420
    static let minWideBoard: CGFloat = 200
    static let wideMinWidth: CGFloat = 700

    /// Wide means 700 points or more and wider than tall, as in Draw & Guess.
    static func isWide(_ size: CGSize) -> Bool {
        size.width >= wideMinWidth && size.width > size.height
    }

    /// The side of the square the board gets in the wide layout.
    static func wideBoardSide(in size: CGSize) -> CGFloat {
        let padding = PaeoniaSpacing.screenHorizontalPadding * 2
        let beside = size.width - sideColumnWidth - PaeoniaSpacing.space32 - padding
        return max(minWideBoard, min(maxWideBoard, beside, size.height - PaeoniaSpacing.space24 * 2))
    }
}

/// The arrangement of a board game screen: the players, the board, the status row
/// and the stake, with the bottom content pinned.
///
/// The board gets up to `BoardGameMetrics.maxBoard` points of width, or a square
/// of the wide layout's side, and fits itself inside that space, for example
/// with `aspectRatio(_:contentMode: .fit)`.
///
/// - A phone and a narrow window show one column that never scrolls. The board
///   shrinks first when the screen is short. The stake sits under the column,
///   above the bottom content, and rises with the keyboard while the starter
///   writes it. The keyboard covers the column instead of squeezing the board.
/// - At accessibility text sizes the column scrolls, the board keeps its size and
///   the stake comes after the status row.
/// - A wide window puts the board on the left and everything else in a column on
///   the right, with the bottom content at the column's bottom.
struct BoardGameScreenLayout<Board: View, Bottom: View>: View {
    let content: BoardGameShellContent
    /// The text the starter writes before the first move.
    @Binding var stakeDraft: String
    let onCommitStake: () -> Void
    /// A board that fills the screen sideways, past the padding, and takes the
    /// height that is left. It fills any space it is given.
    var boardBleeds = false
    @ViewBuilder var board: Board
    /// The invite button, the offline line or the result panel.
    @ViewBuilder var bottom: Bottom

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The height of the right column's rows in the wide layout.
    @State private var wideRowsHeight: CGFloat = 0
    /// The height of the bottom content in the wide layout.
    @State private var wideBottomHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            if BoardGameMetrics.isWide(proxy.size) {
                wide(size: proxy.size)
            } else if dynamicTypeSize.isAccessibilitySize {
                scrolling
            } else {
                fixed
            }
        }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
    }

    // MARK: Rows

    private var playersRow: some View {
        BoardGamePlayersRow(
            me: content.me,
            partner: content.partner,
            turn: content.turn,
            partnerName: content.partner.name
        )
    }

    @ViewBuilder
    private var stakeRow: some View {
        if content.stake != .hidden {
            BoardGameStakeRow(
                state: content.stake,
                draft: $stakeDraft,
                partnerName: content.partner.name,
                onCommitDraft: onCommitStake
            )
        }
    }

    private var statusRow: some View {
        BoardGameStatusRow(
            partnerName: content.partner.name,
            status: content.partnerStatus,
            extraTurnCount: content.extraTurnCount,
            hint: content.hint
        )
    }

    private var scoreHeader: some View {
        BoardGameScoreHeader(score: content.score, me: content.me, partner: content.partner)
    }

    /// The rows above the board.
    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            scoreHeader
            playersRow
        }
    }

    // MARK: Narrow

    private var fixed: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            header
            // Takes the height that is left and centers the board and the status row in it.
            VStack(spacing: PaeoniaSpacing.space12) {
                boardSlot
                statusRow
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space8)
        .paeoniaReadableWidth()
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Outside the bottom bar, which hides while the keyboard is up.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stakeRow
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space8)
                .paeoniaReadableWidth()
                // The board can be under it while the keyboard is up.
                .background(.paeoniaBackgroundSecondary)
                .animation(PaeoniaMotion.stateChange, value: content.stake)
        }
        .paeoniaBottomBar { bottomBar }
    }

    private var scrolling: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space16) {
                header
                boardSlot
                    .aspectRatio(boardBleeds ? 1 : nil, contentMode: .fit)
                statusRow
                stakeRow
            }
            .animation(PaeoniaMotion.stateChange, value: content.stake)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space8)
            .padding(.bottom, PaeoniaSpacing.space16)
            .paeoniaReadableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .paeoniaBottomBar { bottomBar }
    }

    /// The board in the narrow layouts. A board that bleeds takes the whole width of
    /// the screen, past the padding, and all the height the other rows leave.
    private var boardSlot: some View {
        board
            .frame(
                maxWidth: boardBleeds ? .infinity : BoardGameMetrics.maxBoard,
                maxHeight: boardBleeds ? .infinity : nil
            )
            .padding(.horizontal, boardBleeds ? -PaeoniaSpacing.screenHorizontalPadding : 0)
    }

    private var bottomBar: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            bottom
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space8)
        .paeoniaReadableWidth()
        .background(.paeoniaBackgroundSecondary)
    }

    // MARK: Wide

    private func wide(size: CGSize) -> some View {
        let side = BoardGameMetrics.wideBoardSide(in: size)
        // A tall bottom, such as a result panel on a landscape phone, would leave
        // the rows above it no room. It then scrolls with them.
        let scrollsBottom = wideBottomHeight > size.height * 0.55
        let rowsHeight = wideRowsHeight + (scrollsBottom ? 0 : wideBottomHeight)
        // The column is as tall as the board, so its rows line up with the
        // board's edges. It grows only when the rows need more room.
        let columnHeight = min(size.height, max(side, rowsHeight))
        return HStack(alignment: .center, spacing: PaeoniaSpacing.space32) {
            board
                .frame(width: side, height: side)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: PaeoniaSpacing.space12) {
                        header
                        stakeRow
                        statusRow
                        if scrollsBottom {
                            wideBottom
                        }
                    }
                    .padding(.vertical, PaeoniaSpacing.space8)
                    .animation(PaeoniaMotion.stateChange, value: content.stake)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wideRowsHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                if !scrollsBottom {
                    wideBottom
                }
            }
            .frame(width: BoardGameMetrics.sideColumnWidth, height: columnHeight)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var wideBottom: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            bottom
        }
        .padding(.vertical, PaeoniaSpacing.space12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wideBottomHeight = $0 }
    }
}

#if DEBUG
private struct BoardGameLayoutPreview: View {
    let shell: BoardGameShellContent
    var showsResult = false
    @State private var draft = ""
    @State private var isCollapsed = false

    var body: some View {
        BoardGameScreenLayout(
            content: shell,
            stakeDraft: $draft,
            onCommitStake: {},
            board: { BoardGamePreviewData.board },
            bottom: {
                if showsResult {
                    BoardGameResultPanel(
                        content: BoardGamePreviewData.result(),
                        me: shell.me,
                        partner: shell.partner,
                        isCollapsed: $isCollapsed,
                        onPrimary: {}
                    )
                } else {
                    GameInviteButton(invite: .available, partnerName: shell.partner.name, send: {})
                }
            }
        )
        .boardGameScoreToolbar(score: shell.score, me: shell.me, partner: shell.partner)
        .preferredColorScheme(.dark)
    }
}

#Preview("Phone, your turn") {
    NavigationStack {
        BoardGameLayoutPreview(shell: BoardGamePreviewData.shell(partnerStatus: .away))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Connect Four")
    }
}

#Preview("Starter writes a stake") {
    NavigationStack {
        BoardGameLayoutPreview(shell: BoardGamePreviewData.shell(stake: .writable))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Connect Four")
    }
}

#Preview("Phone, result") {
    NavigationStack {
        BoardGameLayoutPreview(
            shell: BoardGamePreviewData.shell(turn: .youWon),
            showsResult: true
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Connect Four")
    }
}

#Preview("Accessibility size") {
    NavigationStack {
        BoardGameLayoutPreview(shell: BoardGamePreviewData.shell(turn: .partnerTurn))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Connect Four")
    }
    .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Wide", traits: .landscapeLeft) {
    NavigationStack {
        BoardGameLayoutPreview(shell: BoardGamePreviewData.shell(), showsResult: true)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Connect Four")
    }
}
#endif

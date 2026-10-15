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

extension EnvironmentValues {
    /// The share of a board view's height, around its middle, that the board fits in.
    /// A board that bleeds draws past the space the layout gave it, so it fits in less than all of its view.
    @Entry var boardFitHeight: CGFloat = 1
}

/// The arrangement of a board game screen: the players, the board, the status row,
/// Ludo's color circles and the stake, with the bottom content pinned.
///
/// The board gets up to `BoardGameMetrics.maxBoard` points of width, or a square
/// of the wide layout's side, and fits itself inside that space, for example
/// with `aspectRatio(_:contentMode: .fit)`.
///
/// - A phone and a narrow window show one column that never scrolls. The board
///   shrinks first when the screen is short. The rows keep to a readable width,
///   and a board that bleeds draws over the whole screen behind the rows. It fits
///   itself in the space between them, and the screen color fades over it outside
///   that space. The color circles and the stake sit under the column, above the
///   bottom content, and the stake rises with the keyboard while the starter
///   writes it. The keyboard covers the column instead of squeezing the board.
/// - At accessibility text sizes the column scrolls, the board keeps its size and
///   the stake comes after the status row.
/// - A wide window puts the board on the left and everything else in a column on
///   the right, with the bottom content at the column's bottom. A board that
///   bleeds, like Ludo's, keeps the one column there too.
struct BoardGameScreenLayout<Board: View, Bottom: View>: View {
    let content: BoardGameShellContent
    /// The text the starter writes before the first move.
    @Binding var stakeDraft: String
    let onCommitStake: () -> Void
    /// A board that fills the screen sideways, past the padding, and takes the
    /// height that is left. It fills any space it is given.
    var boardBleeds = false
    /// A tap on one of Ludo's color circles.
    let onPickColor: (LudoColor) -> Void
    @ViewBuilder var board: Board
    /// The invite button, the offline line or the result panel.
    @ViewBuilder var bottom: Bottom

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The height of the right column's rows in the wide layout.
    @State private var wideRowsHeight: CGFloat = 0
    /// The height of the bottom content in the wide layout.
    @State private var wideBottomHeight: CGFloat = 0
    /// Where a board that bleeds fits, in global coordinates.
    @State private var bleedSlotFrame: CGRect = .zero

    /// How far the cover takes to fade in past the edge of the space the board fits in.
    /// A long, eased fade has no edge the eye can catch.
    private static var bleedCoverFade: CGFloat { 140 }
    /// How much of the board the cover hides above and below that space.
    private static var bleedCoverOpacity: Double { 0.85 }

    var body: some View {
        GeometryReader { proxy in
            // A board that bleeds keeps the one column on a wide screen too, so it spans
            // the whole width instead of a box beside the rows.
            if !boardBleeds, BoardGameMetrics.isWide(proxy.size) {
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
            partnerName: content.partner.name,
            partnerIsHere: content.partnerStatus == .here
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

    @ViewBuilder
    private var colorRow: some View {
        if let choice = content.colorChoice {
            BoardGameColorPicker(choice: choice, onPick: onPickColor)
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
                .paeoniaReadableWidth()
            // Takes the height that is left and centers the board and the status row in it.
            VStack(spacing: PaeoniaSpacing.space12) {
                if boardBleeds {
                    bleedSlot
                } else {
                    boardSlot
                }
                statusRow
                    .paeoniaReadableWidth()
                    // The invite comes and goes with the turn, and the row glides with the board.
                    .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: content.turn)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space8)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Outside the bottom bar, which hides while the keyboard is up.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: PaeoniaSpacing.space4) {
                colorRow
                stakeRow
            }
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.space8)
            .paeoniaReadableWidth()
            // The board can be under it while the keyboard is up. A board that bleeds is covered there instead.
            .background(boardBleeds ? Color.clear : .paeoniaBackgroundSecondary)
            .animation(PaeoniaMotion.stateChange, value: content.stake)
            .animation(PaeoniaMotion.stateChange, value: content.colorChoice != nil)
        }
        .paeoniaBottomBar { bottomBar }
        .background {
            if boardBleeds {
                bleedingBoard
            }
        }
    }

    private var scrolling: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space16) {
                header
                boardSlot
                    .aspectRatio(boardBleeds ? 1 : nil, contentMode: .fit)
                statusRow
                colorRow
                stakeRow
            }
            .animation(PaeoniaMotion.stateChange, value: content.stake)
            .animation(PaeoniaMotion.stateChange, value: content.colorChoice != nil)
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
        .background(boardBleeds && !dynamicTypeSize.isAccessibilitySize ? Color.clear : .paeoniaBackgroundSecondary)
    }

    // MARK: Bleed

    /// The space a board that bleeds fits in. It stays empty, so touches pass through
    /// to the board behind it.
    private var bleedSlot: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                // The bottom bar grows and shrinks as the invite comes and goes, and the
                // board glides to its new space instead of jumping. The first layout and a
                // turned screen snap.
                let isSameColumn = frame.minX == bleedSlotFrame.minX && frame.width == bleedSlotFrame.width
                if isSameColumn, bleedSlotFrame.height > 0, !reduceMotion {
                    withAnimation(PaeoniaMotion.stateChange) { bleedSlotFrame = frame }
                } else {
                    bleedSlotFrame = frame
                }
            }
    }

    /// The board over the whole screen, behind the rows. It reaches as far above and
    /// below the slot as the farther edge of the screen, so the slot stays in its middle
    /// and the board fits there. Past the slot's top and bottom the screen color fades in over it.
    private var bleedingBoard: some View {
        GeometryReader { proxy in
            let screen = proxy.frame(in: .global)
            BoardGameAnimatedSlot(slot: bleedSlotFrame.offsetBy(dx: -screen.minX, dy: -screen.minY)) { slot in
                // ponytail: the view runs past the nearer screen edge and draws pixels nobody sees.
                // Shift the camera's lens off center instead if that costs frames on an iPad.
                let reach = max(slot.minY, screen.height - slot.maxY, 0)
                let height = slot.height + reach * 2
                if slot.height > 0 {
                    ZStack {
                        board
                            .environment(\.boardFitHeight, slot.height / height)
                        bleedCover(reach: reach, slotHeight: slot.height)
                    }
                    .frame(width: screen.width, height: height)
                    .position(x: screen.width / 2, y: slot.midY)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// The screen color over the board above and below the slot, clear inside it.
    /// It is not a material: a material can't blur the 3D view behind it and adds its
    /// own gray tint, which shows as frosted strips even over the plain background.
    private func bleedCover(reach: CGFloat, slotHeight: CGFloat) -> some View {
        let height = reach * 2 + slotHeight
        let fade = Self.bleedCoverFade
        func at(_ y: CGFloat) -> CGFloat { min(max(y / height, 0), 1) }
        // Clear at `edge`, easing in to full over `fade` points in `direction`. A
        // smoothstep curve has no kink where it starts or ends, unlike a straight ramp.
        func ramp(from edge: CGFloat, direction: CGFloat) -> [Gradient.Stop] {
            let steps = 16
            return (0...steps).map { step in
                let share = CGFloat(step) / CGFloat(steps)
                let eased = share * share * (3 - 2 * share)
                return .init(color: .black.opacity(eased), location: at(edge + direction * share * fade))
            }
        }
        let mask = LinearGradient(
            stops: [.init(color: .black, location: 0)]
                + ramp(from: reach, direction: -1).reversed()
                + ramp(from: reach + slotHeight, direction: 1)
                + [.init(color: .black, location: 1)],
            startPoint: .top,
            endPoint: .bottom
        )
        return Color.paeoniaBackgroundSecondary
            .opacity(Self.bleedCoverOpacity)
            .mask(mask)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
                        colorRow
                        stakeRow
                        statusRow
                        if scrollsBottom {
                            wideBottom
                        }
                    }
                    .padding(.vertical, PaeoniaSpacing.space8)
                    .animation(PaeoniaMotion.stateChange, value: content.stake)
                    .animation(PaeoniaMotion.stateChange, value: content.colorChoice != nil)
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

/// Hands its content the space a board that bleeds fits in. It is animatable, so
/// when that space changes, the content is laid out again on every frame of the
/// animation. The board's view and its camera then follow the space smoothly
/// instead of jumping to the end.
private struct BoardGameAnimatedSlot<Content: View>: View, Animatable {
    var slot: CGRect
    @ViewBuilder let content: (CGRect) -> Content

    var animatableData: CGRect.AnimatableData {
        get { slot.animatableData }
        set { slot.animatableData = newValue }
    }

    var body: some View {
        content(slot)
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
            onPickColor: { _ in },
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

#Preview("Ludo, pick a color") {
    NavigationStack {
        BoardGameLayoutPreview(
            shell: BoardGamePreviewData.shell(
                stake: .writable,
                colorChoice: BoardGameColorChoice(
                    colors: .standard,
                    partnerName: "Robin",
                    partnerInitial: "R"
                )
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Ludo")
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

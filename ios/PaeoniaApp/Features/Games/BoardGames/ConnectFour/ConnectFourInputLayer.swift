import SwiftUI

/// The top layer of the board. It takes touches, shows the hovering disc, and
/// gives VoiceOver one element for each column.
///
/// A touch shows my disc above the column under the finger. Dragging moves it
/// from column to column with a tap for each one. Lifting the finger drops it. A
/// tap is a drag that never moves, so it drops at once. A full column shakes the
/// disc and sends nothing.
struct ConnectFourInputLayer: View {
    let geometry: ConnectFourBoardGeometry
    let board: ConnectFourBoard
    /// My pieces.
    let myStyle: BoardPieceStyle
    let me: BoardPlayer
    let canPlay: Bool
    /// The newest move's number. When it changes, the hovering disc hands over
    /// to the falling disc, which starts in the same spot.
    let moveNumber: Int?
    let onPlay: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isTouching = false
    @State private var hoverColumn = ConnectFourBoardGeometry.columns / 2
    @State private var isHovering = false
    @State private var shakes = 0
    /// The finger is up and the move was sent. The disc waits for the board to show it.
    @State private var isAwaitingMove = false
    @State private var hideDelay: Duration?
    @State private var hideToken = 0

    /// If the board never shows the move, the hovering disc goes away after this.
    private static let awaitTimeout = Duration.milliseconds(700)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
            columnElements
            hoverDisc
        }
        .frame(width: geometry.width, height: geometry.totalHeight, alignment: .topLeading)
        .gesture(dragGesture, including: canPlay ? .all : .none)
        .onChange(of: isTouching) { cancelIfTouchWasInterrupted() }
        .onChange(of: moveNumber) { handOver() }
        .onChange(of: canPlay) {
            if !canPlay, !isAwaitingMove { hide() }
        }
        .task(id: hideToken) { await hideAfterDelay() }
    }

    // MARK: Hovering disc

    private var hoverDisc: some View {
        let isBlocked = board.landingRow(column: hoverColumn) == nil
        return ConnectFourDiscView(style: myStyle, diameter: geometry.discDiameter)
            .shadow(color: Color.black.opacity(0.3), radius: 6, y: 4)
            .scaleEffect((reduceMotion || isHovering) ? 1 : 0.6)
            .opacity(isHovering ? (isBlocked ? 0.45 : 1) : 0)
            .modifier(DrawAndGuessShake(trigger: shakes, isEnabled: !reduceMotion))
            .position(geometry.hoverCenter(column: hoverColumn))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var appearAnimation: Animation {
        reduceMotion
            ? PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionFast)
            : .spring(duration: 0.22, bounce: 0.25)
    }

    private var moveAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.2, bounce: 0.15)
    }

    // MARK: Touch

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { value in track(geometry.column(forX: value.location.x)) }
            .onEnded { value in release(geometry.column(forX: value.location.x)) }
    }

    private func track(_ column: Int) {
        guard canPlay, !isAwaitingMove else { return }
        if hideDelay != nil { cancelHide() }
        if !isHovering {
            // Put the disc over the column first, so it fades in there instead of sliding in.
            hoverColumn = column
            withAnimation(appearAnimation) { isHovering = true }
            PaeoniaHaptics.selection()
        } else if hoverColumn != column {
            withAnimation(moveAnimation) { hoverColumn = column }
            PaeoniaHaptics.selection()
        }
    }

    private func release(_ column: Int) {
        guard canPlay else {
            hide()
            return
        }
        guard !isAwaitingMove else { return }
        drop(in: isHovering ? hoverColumn : column)
    }

    /// Sends a move, or shakes the disc when the column is full. Touch and
    /// VoiceOver both end here, and the guards make one gesture send one move.
    private func drop(in column: Int) {
        guard canPlay, !isAwaitingMove else { return }
        guard board.landingRow(column: column) != nil else {
            shakes += 1
            PaeoniaHaptics.gameWrongGuess()
            schedule(hideAfter: .milliseconds(reduceMotion ? 300 : 500))
            return
        }
        isAwaitingMove = true
        schedule(hideAfter: Self.awaitTimeout)
        onPlay(column)
    }

    /// The system can end a touch without a lift, for example a call coming in.
    private func cancelIfTouchWasInterrupted() {
        guard !isTouching, isHovering, !isAwaitingMove, hideDelay == nil else { return }
        schedule(hideAfter: .milliseconds(150))
    }

    // MARK: Hiding

    private func schedule(hideAfter delay: Duration) {
        hideDelay = delay
        hideToken += 1
    }

    private func cancelHide() {
        hideDelay = nil
        hideToken += 1
    }

    private func hide() {
        withAnimation(appearAnimation) { isHovering = false }
    }

    private func hideAfterDelay() async {
        guard let delay = hideDelay else { return }
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        hideDelay = nil
        isAwaitingMove = false
        hide()
    }

    /// The board shows the move now, so the falling disc takes over from this
    /// one. It goes away at once, because the falling disc is already there.
    private func handOver() {
        isAwaitingMove = false
        cancelHide()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isHovering = false }
    }

    // MARK: VoiceOver

    private var columnElements: some View {
        HStack(spacing: 0) {
            ForEach(0..<ConnectFourBoardGeometry.columns, id: \.self) { column in
                columnElement(column)
            }
        }
        .padding(.leading, geometry.inset)
    }

    @ViewBuilder
    private func columnElement(_ column: Int) -> some View {
        let element = Color.clear
            .frame(width: geometry.cell, height: geometry.totalHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(for: column))
            .accessibilityIdentifier("connectFour.column.\(column)")
        if canPlay, board.landingRow(column: column) != nil {
            element
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { drop(in: column) }
                .accessibilityAction(named: Text(.connectFourColumnDrop)) { drop(in: column) }
        } else {
            element
        }
    }

    /// "Column 3, 2 discs, yours on top", "Column 3, empty" or "Column 3, full".
    private func label(for column: Int) -> String {
        let name = String(localized: .connectFourColumnLabel(column + 1))
        guard let top = board.topDiscIndex(column: column), let owner = board.cells[top] else {
            return [name, String(localized: .connectFourColumnEmpty)].joined(separator: ", ")
        }
        guard board.landingRow(column: column) != nil else {
            return [name, String(localized: .connectFourColumnFull)].joined(separator: ", ")
        }
        let discs = String(localized: .connectFourColumnDiscs(board.discCount(inColumn: column)))
        let onTop = owner == me
            ? String(localized: .connectFourColumnTopMine)
            : String(localized: .connectFourColumnTopPartner)
        return [name, discs, onTop].joined(separator: ", ")
    }
}

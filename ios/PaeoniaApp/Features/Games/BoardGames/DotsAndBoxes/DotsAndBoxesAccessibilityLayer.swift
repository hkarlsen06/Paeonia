import SwiftUI

/// The four sides of a box, in the order `DotsAndBoxesBoard.lines(of:)` lists them.
enum DotsAndBoxesSide: Int, CaseIterable, Identifiable {
    case top
    case bottom
    case left
    case right

    var id: Int { rawValue }

    /// The side as a word in a sentence, such as "top".
    var word: LocalizedStringResource {
        switch self {
        case .top: .dotsAndBoxesSideTop
        case .bottom: .dotsAndBoxesSideBottom
        case .left: .dotsAndBoxesSideLeft
        case .right: .dotsAndBoxesSideRight
        }
    }

    /// The VoiceOver action that draws this side.
    var action: LocalizedStringResource {
        switch self {
        case .top: .dotsAndBoxesActionTop
        case .bottom: .dotsAndBoxesActionBottom
        case .left: .dotsAndBoxesActionLeft
        case .right: .dotsAndBoxesActionRight
        }
    }
}

/// The board for VoiceOver: a grid of 16 boxes. Each box reads who closed it or
/// which sides are drawn, and offers one action per open side while it is my turn.
/// Nothing here draws.
struct DotsAndBoxesAccessibilityLayer: View {
    let board: DotsAndBoxesBoard
    let geometry: DotsAndBoxesBoardGeometry
    let me: BoardPlayer
    /// The partner's name as VoiceOver says it.
    let partnerName: String
    let canPlay: Bool
    let onPlay: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<DotsAndBoxesBoard.boxTotal, id: \.self) { box in
                let rect = geometry.boxRect(box)
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(for: box))
                    .accessibilityIdentifier("dotsAndBoxes.box.\(box)")
                    .accessibilityActions { actions(for: box) }
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func label(for box: Int) -> Text {
        let count = DotsAndBoxesBoard.boxesPerSide
        let row = box / count + 1
        let column = box % count + 1
        if let owner = board.boxes[box] {
            return owner == me
                ? Text(.dotsAndBoxesBoxMine(row, column))
                : Text(.dotsAndBoxesBoxPartner(row, column, partnerName))
        }
        let lines = DotsAndBoxesBoard.lines(of: box)
        let drawn = DotsAndBoxesSide.allCases
            .filter { board.lines[lines[$0.rawValue]] != nil }
            .map { String(localized: $0.word) }
        if drawn.isEmpty {
            return Text(.dotsAndBoxesBoxEmpty(row, column))
        }
        return Text(.dotsAndBoxesBoxSides(row, column, drawn.formatted(.list(type: .and))))
    }

    @ViewBuilder
    private func actions(for box: Int) -> some View {
        if canPlay {
            let lines = DotsAndBoxesBoard.lines(of: box)
            ForEach(DotsAndBoxesSide.allCases) { side in
                let line = lines[side.rawValue]
                if board.lines[line] == nil {
                    Button {
                        onPlay(line)
                    } label: {
                        Text(side.action)
                    }
                }
            }
        }
    }
}

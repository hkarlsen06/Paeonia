import SwiftUI

/// Inspect any box without traversing four repeated actions for every earlier box.
/// The grid keeps its own spatial elements and actions; this form calls the same move callback.
struct DotsAndBoxesNativeControls: View {
    let board: DotsAndBoxesBoard
    let me: BoardPlayer
    let partnerName: String
    let canPlay: Bool
    let onPlay: (Int) -> Void
    @State private var inspectedBox = 0

    var body: some View {
        Section {
            Menu {
                ForEach(0..<DotsAndBoxesBoard.boxTotal, id: \.self) { box in
                    Button { inspectedBox = box } label: {
                        HStack {
                            boxLabel(box)
                            if inspectedBox == box {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                    }
                    .accessibilityAddTraits(inspectedBox == box ? .isSelected : [])
                    .accessibilityIdentifier("dotsAndBoxes.native.box.\(box)")
                }
            } label: {
                Label(.dotsAndBoxesControlsChooseBox, systemImage: "square.grid.3x3")
                    .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityValue(boxLabel(inspectedBox))
            .accessibilityIdentifier("dotsAndBoxes.native.box")
        }

        Section {
            boxLabel(inspectedBox)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("dotsAndBoxes.box.\(inspectedBox).state")
            ForEach(DotsAndBoxesSide.allCases) { side in
                let line = DotsAndBoxesBoard.lines(of: inspectedBox)[side.rawValue]
                Button { onPlay(line) } label: {
                    Text(side.action)
                        .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
                }
                .disabled(!canPlay || board.lines[line] != nil)
                .accessibilityIdentifier("dotsAndBoxes.box.\(inspectedBox).side.\(side.rawValue)")
            }
        }
    }

    private func boxLabel(_ box: Int) -> Text {
        DotsAndBoxesAccessibilityLayer.boxLabel(board: board, box: box, me: me, partnerName: partnerName)
    }
}

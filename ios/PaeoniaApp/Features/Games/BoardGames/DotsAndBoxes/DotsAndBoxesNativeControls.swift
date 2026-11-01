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
            // Long box states need a full native list at accessibility text sizes.
            Picker(selection: $inspectedBox) {
                ForEach(0..<DotsAndBoxesBoard.boxTotal, id: \.self) { box in
                    boxLabel(box)
                        .fixedSize(horizontal: false, vertical: true)
                        .tag(box)
                        .accessibilityIdentifier("dotsAndBoxes.native.box.\(box)")
                }
            } label: {
                Label(.dotsAndBoxesControlsChooseBox, systemImage: "square.grid.3x3")
                    .frame(minHeight: PaeoniaSpacing.compactButtonHeight)
            }
            .pickerStyle(.navigationLink)
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

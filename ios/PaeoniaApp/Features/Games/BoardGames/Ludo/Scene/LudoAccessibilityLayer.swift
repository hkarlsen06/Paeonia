import SwiftUI

/// What VoiceOver gets instead of the 3D picture: the die, and each of my pawns
/// that can move. The elements sit where the pieces show on screen, so the
/// focus ring lands on them. The layer takes no touches. The pieces take those.
struct LudoAccessibilityLayer: View {
    let board: LudoBoard
    let me: BoardPlayer
    let die: LudoDieState
    let movableChoices: [LudoChoice]
    let rig: LudoCameraRig
    let size: CGSize
    let onRoll: () -> Void
    let onChoose: (LudoChoice) -> Void

    private static let elementSide: CGFloat = 44

    private struct PawnElement: Identifiable {
        let choice: LudoChoice
        let index: Int
        let center: CGPoint
        var id: Int { index }
    }

    var body: some View {
        ZStack {
            dieElement
            ForEach(pawnElements) { element in
                pawnView(element)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(.ludoBoardLabel))
    }

    // MARK: Die

    @ViewBuilder
    private var dieElement: some View {
        let center = screenPoint(LudoWorld.dieRestPosition(isNear: die.side(me: me) == me))
        switch die {
        case .ready:
            marker(at: center)
                .accessibilityLabel(Text(.ludoDieRoll))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onRoll() }
        case let .showing(value, _):
            marker(at: center)
                .accessibilityLabel(Text(.ludoDieRolled(value)))
        case .idle, .rolling:
            EmptyView()
        }
    }

    // MARK: Pawns

    private var pawnElements: [PawnElement] {
        let placements = LudoBoardGeometry.placements(board: board, viewer: me)
        return movableChoices.compactMap { choice in
            guard choice != .pass else { return nil }
            let index = LudoBoard.pawnIndex(me, choice.rawValue)
            guard placements.indices.contains(index) else { return nil }
            var world = LudoWorld.position(of: placements[index])
            world.y += LudoSceneStyle.pawnHeight / 2
            return PawnElement(choice: choice, index: index, center: screenPoint(world))
        }
    }

    @ViewBuilder
    private func pawnView(_ element: PawnElement) -> some View {
        let squaresLeft = LudoBoard.homeProgress - board.progress[element.index]
        let label = Text(.ludoPawnMovable(element.choice.rawValue + 1, squaresLeft))
        if let value = die.value {
            marker(at: element.center)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onChoose(element.choice) }
                .accessibilityAction(named: Text(.ludoPawnMove(value))) { onChoose(element.choice) }
        } else {
            marker(at: element.center)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onChoose(element.choice) }
        }
    }

    // MARK: Helpers

    private func marker(at center: CGPoint) -> some View {
        Color.clear
            .frame(width: Self.elementSide, height: Self.elementSide)
            .contentShape(Rectangle())
            .position(center)
            .accessibilityElement()
    }

    private func screenPoint(_ world: SIMD3<Float>) -> CGPoint {
        guard let unit = rig.project(world) else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        return CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }
}

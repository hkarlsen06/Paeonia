import Testing
import UIKit
@testable import PaeoniaApp

/// The four pawn colors and how the board hands them to its corners.
@MainActor
struct LudoColorTests {
    @Test func theColorsNobodyPickedAreTheEmptyCornersInTheOrderOfTheFourColors() {
        #expect(LudoColorPair.standard.unused == [.gold, .sky])
        #expect(LudoColorPair(mine: .gold, partner: .pink).unused == [.lavender, .sky])
        #expect(LudoColorPair(mine: .sky, partner: .lavender).unused == [.pink, .gold])
    }

    @Test func theServersNamesAreTheRawValues() {
        #expect(LudoColor.allCases.map(\.rawValue) == ["pink", "lavender", "gold", "sky"])
    }

    @Test func eachColorLooksDifferent() {
        #expect(Set(LudoColor.allCases.map { $0.uiColor.description }).count == 4)
    }

    @Test(arguments: [BoardPlayer.one, .two])
    func thePlayersCornersTakeTheirPickedColorsAndTheOthersTakeTheRest(viewer: BoardPlayer) {
        let pair = LudoColorPair(mine: .gold, partner: .pink)
        let colors = LudoSceneBuilder.CornerColors(viewer: viewer, colors: pair)

        #expect(colors.color(ofCorner: LudoBoardGeometry.corner(of: viewer)) == LudoColor.gold.uiColor)
        #expect(colors.color(ofCorner: LudoBoardGeometry.corner(of: viewer.other)) == LudoColor.pink.uiColor)
        let empty = (0..<4)
            .filter { [.gold, .sky].contains(LudoBoardGeometry.role(ofCorner: $0, viewer: viewer)) }
            .map { colors.color(ofCorner: $0) }
        #expect(Set(empty.map(\.description)) == Set([LudoColor.lavender, .sky].map { $0.uiColor.description }))
    }

    @Test func theStandardPairKeepsGoldAtTheTopLeftAndSkyBlueAtTheBottomRight() {
        let colors = LudoSceneBuilder.CornerColors(viewer: .one, colors: .standard)
        let topLeft = (0..<4).first { LudoBoardGeometry.role(ofCorner: $0, viewer: .one) == .gold }
        let bottomRight = (0..<4).first { LudoBoardGeometry.role(ofCorner: $0, viewer: .one) == .sky }

        #expect(topLeft.map { colors.color(ofCorner: $0) } == LudoColor.gold.uiColor)
        #expect(bottomRight.map { colors.color(ofCorner: $0) } == LudoColor.sky.uiColor)
    }
}

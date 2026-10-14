import Foundation
import Testing
@testable import PaeoniaApp

/// Both phones work out the same ids, and different parts never share one.
struct ExquisiteCorpseIDsTests {
    private let game = UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1))
    private let me = UUID(uuid: (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2))
    private let partner = UUID(uuid: (3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3))

    private func part(figure: Int, index: Int, drawer: UUID) -> UUID {
        ExquisiteCorpseIDs.part(gameID: game, figureNumber: figure, partIndex: index, drawerID: drawer)
    }

    @Test func theSameInputsGiveTheSameIDs() {
        #expect(part(figure: 3, index: 1, drawer: me) == part(figure: 3, index: 1, drawer: me))
        let figure = ExquisiteCorpseIDs.figure(gameID: game, number: 3)
        #expect(figure == ExquisiteCorpseIDs.figure(gameID: game, number: 3))
    }

    @Test func everyPartAndFigureHasItsOwnID() {
        var ids: Set<UUID> = []
        for number in 1...4 {
            ids.insert(ExquisiteCorpseIDs.figure(gameID: game, number: number))
            for index in 0...2 {
                for drawer in [me, partner] {
                    ids.insert(part(figure: number, index: index, drawer: drawer))
                }
            }
        }
        #expect(ids.count == 4 + 4 * 3 * 2)
    }

    @Test func theIDsAreVersionFive() {
        let text = part(figure: 1, index: 0, drawer: me).uuidString
        #expect(text.dropFirst(14).first == "5")
        #expect(text.dropFirst(19).first.map { "89AB".contains($0) } == true)
    }
}

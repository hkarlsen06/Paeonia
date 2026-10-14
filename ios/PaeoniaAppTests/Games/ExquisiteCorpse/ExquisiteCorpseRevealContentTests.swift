import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

@MainActor
struct ExquisiteCorpseRevealContentTests {
    private typealias Content = ExquisiteCorpseRevealContent

    private let robin = GamePlayer(name: "Robin", photoAssetID: nil)
    private let me = GamePlayer(name: "Hjalmar", photoAssetID: nil)

    private func part(
        _ kind: ExquisiteCorpsePartKind,
        drawing: PKDrawing? = PKDrawing(),
        mine: Bool = false,
        idea: String? = nil
    ) -> Content.Part {
        Content.Part(kind: kind, drawing: drawing, drawerIsMe: mine, drawer: mine ? me : robin, idea: idea)
    }

    private func content(_ parts: [Content.Part]) -> Content {
        Content(figureID: UUID(), number: 12, parts: parts, partnerName: "Robin", nextIsMine: true)
    }

    @Test func theRevealWaitsUntilAllThreeDrawingsAreOnThePhone() {
        let loaded = content([part(.head), part(.body), part(.legs)])
        let waiting = content([part(.head), part(.body, drawing: nil), part(.legs)])

        #expect(loaded.isReady)
        #expect(!waiting.isReady)
    }

    @Test func aFigureWithMissingPartsIsNeverReady() {
        #expect(!content([part(.head), part(.body)]).isReady)
        #expect(!content([]).isReady)
    }

    @Test func theLoadedDrawingsAreFoundByPart() {
        let waiting = content([part(.head), part(.body, drawing: nil), part(.legs)])

        #expect(Set(waiting.drawings.keys) == [.head, .legs])
        #expect(waiting.part(.body)?.drawing == nil)
        #expect(waiting.part(.legs)?.drawer == robin)
    }

    @Test func theCreditNamesWhoDrewThePartAndSaysYouForMyOwn() {
        let theirs = part(.head)
        let mine = part(.body, mine: true)

        #expect(theirs.drawerName == "Robin")
        #expect(mine.drawerName == String(localized: .exquisiteCorpseRevealYou))
        #expect(theirs.credit.contains("Robin"))
        #expect(mine.credit.contains(mine.drawerName))
    }

    @Test func theSpokenCreditAddsTheIdeaAfterAComma() {
        let withIdea = part(.head, idea: "a grandma")
        let without = part(.legs)

        #expect(withIdea.spokenCredit == "\(withIdea.credit), a grandma.")
        #expect(without.spokenCredit == "\(without.credit).")
    }

    @Test func theSpokenCreditsListEveryPartInOrder() {
        let figure = content([part(.head, idea: "a grandma"), part(.body, mine: true), part(.legs)])

        #expect(figure.spokenCredits == figure.parts.map(\.spokenCredit).joined(separator: " "))
    }
}

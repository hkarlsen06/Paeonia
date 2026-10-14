import PencilKit
import SwiftUI

/// Everything the reveal needs to show one finished figure. The screen builds it
/// and passes it in, so the reveal holds no game rules. A part whose drawing is
/// still downloading has a nil `drawing`, and the reveal waits with the folded
/// paper until all three are there.
struct ExquisiteCorpseRevealContent {
    struct Part: Identifiable {
        let kind: ExquisiteCorpsePartKind
        /// At the canonical side. Nil while it loads.
        let drawing: PKDrawing?
        let drawerIsMe: Bool
        /// The name and photo for the avatar.
        let drawer: GamePlayer
        /// The idea the drawer had when they tapped Done, if any.
        let idea: String?

        var id: ExquisiteCorpsePartKind { kind }

        /// "you" for my own parts, so the credit reads "Body by you".
        var drawerName: String {
            drawerIsMe ? String(localized: .exquisiteCorpseRevealYou) : drawer.name
        }

        /// "Head by Robin".
        var credit: String {
            switch kind {
            case .head: String(localized: .exquisiteCorpseRevealCreditHead(drawerName))
            case .body: String(localized: .exquisiteCorpseRevealCreditBody(drawerName))
            case .legs: String(localized: .exquisiteCorpseRevealCreditLegs(drawerName))
            }
        }

        /// "Head by Robin, a grandma." for VoiceOver.
        var spokenCredit: String {
            guard let idea else { return credit + "." }
            return "\(credit), \(idea)."
        }
    }

    let figureID: UUID
    /// The creature's number, counting from 1.
    let number: Int
    /// The head, the body and the legs, in that order.
    let parts: [Part]
    let partnerName: String
    /// The next figure starts with me, so the button says "Draw the next head".
    let nextIsMine: Bool

    /// All three drawings are on the phone.
    var isReady: Bool {
        parts.count == ExquisiteCorpsePartKind.allCases.count && parts.allSatisfy { $0.drawing != nil }
    }

    /// The drawings that are loaded, by part.
    var drawings: [ExquisiteCorpsePartKind: PKDrawing] {
        Dictionary(parts.compactMap { part in part.drawing.map { (part.kind, $0) } }) { _, last in last }
    }

    func part(_ kind: ExquisiteCorpsePartKind) -> Part? {
        parts.first { $0.kind == kind }
    }

    /// "Head by Robin, a grandma. Body by you. Legs by Robin." for the VoiceOver
    /// announcement.
    var spokenCredits: String {
        parts.map(\.spokenCredit).joined(separator: " ")
    }
}

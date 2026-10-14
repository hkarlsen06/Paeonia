#if DEBUG
import SwiftUI

extension ExquisiteCorpseRevealContent {
    /// Creature 12 for previews. The viewer drew the body, Robin the head and the legs.
    /// With `isLoaded` false the drawings are still on their way.
    static func preview(isLoaded: Bool = true, nextIsMine: Bool = true) -> Self {
        let robin = GamePlayer(name: "Robin")
        let me = GamePlayer(name: "Hjalmar")
        return Self(
            figureID: UUID(uuidString: "5C1B7F6E-2D4A-4C0E-9F53-7A1D2E3B4C5D") ?? UUID(),
            number: 12,
            parts: [
                Part(
                    kind: .head,
                    drawing: isLoaded ? ExquisiteCorpsePreviewDrawings.head : nil,
                    drawerIsMe: false,
                    drawer: robin,
                    idea: "a grandma"
                ),
                Part(
                    kind: .body,
                    drawing: isLoaded ? ExquisiteCorpsePreviewDrawings.body : nil,
                    drawerIsMe: true,
                    drawer: me,
                    idea: nil
                ),
                Part(
                    kind: .legs,
                    drawing: isLoaded ? ExquisiteCorpsePreviewDrawings.legs : nil,
                    drawerIsMe: false,
                    drawer: robin,
                    idea: "frog legs"
                ),
            ],
            partnerName: "Robin",
            nextIsMine: nextIsMine
        )
    }
}

#Preview("Reveal") {
    ExquisiteCorpseRevealView(content: .preview(), reduceMotion: false, onContinue: {})
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
}

#Preview("Opening") {
    ExquisiteCorpseRevealView(content: .preview(isLoaded: false), reduceMotion: false, onContinue: {})
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
}

#Preview("Reduce Motion") {
    ExquisiteCorpseRevealView(content: .preview(nextIsMine: false), reduceMotion: true, onContinue: {})
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    ExquisiteCorpseRevealView(content: .preview(), reduceMotion: true, onContinue: {})
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .dynamicTypeSize(.accessibility3)
        .preferredColorScheme(.dark)
}
#endif

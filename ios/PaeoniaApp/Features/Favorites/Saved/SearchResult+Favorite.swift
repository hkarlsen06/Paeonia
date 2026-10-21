import Foundation

extension SearchResult {
    /// A starred item as a Search row, so the starred list uses the rows and the navigation
    /// that Search already has. Nil when the server sent too little to show a row.
    init?(favorite: FavoriteSummary, people: StoryPeople, locale: Locale = .current) {
        let result: SearchResult?
        switch favorite.target.kind {
        case .dailyQuestion: result = Self.question(favorite, locale: locale)
        case .dailyAnswer: result = Self.answer(favorite, people: people, locale: locale)
        case .widgetDrawing: result = Self.drawing(favorite)
        case .gameRound, .corpseFigure, .storyChainStory: result = Self.gameItem(favorite)
        }
        guard let result else { return nil }
        self = result
    }

    private static func question(_ favorite: FavoriteSummary, locale: Locale) -> SearchResult? {
        guard let prompt = favorite.prompt(for: locale) else { return nil }
        return SearchResult(
            kind: .question,
            key: favorite.target.id,
            title: prompt,
            date: favorite.occurredAt,
            destination: .question(favorite.questionID ?? favorite.target.id)
        )
    }

    private static func answer(_ favorite: FavoriteSummary, people: StoryPeople, locale: Locale) -> SearchResult? {
        guard let questionID = favorite.questionID else { return nil }
        return SearchResult(
            kind: .answer,
            key: favorite.target.id,
            title: answerText(of: favorite, people: people, locale: locale),
            detail: favorite.prompt(for: locale),
            authorUserID: favorite.authorUserID,
            date: favorite.occurredAt,
            destination: .question(questionID)
        )
    }

    private static func drawing(_ favorite: FavoriteSummary) -> SearchResult {
        SearchResult(
            kind: .drawing,
            key: favorite.target.id,
            title: String(localized: .favoritesRowDrawing),
            authorUserID: favorite.authorUserID,
            date: favorite.occurredAt,
            destination: .widgetDrawing(favorite.target.id)
        )
    }

    /// A finished round, creature or story of a game.
    private static func gameItem(_ favorite: FavoriteSummary) -> SearchResult? {
        let id = favorite.target.id
        switch favorite.target.kind {
        case .gameRound:
            return SearchResult(
                kind: .round,
                key: id,
                title: favorite.title.map(DrawAndGuessAnswer.display),
                label: String(localized: GameKind.drawAndGuess.name),
                date: favorite.occurredAt,
                destination: .drawAndGuessRound(id)
            )
        case .corpseFigure:
            return SearchResult(
                kind: .creature,
                key: id,
                title: String(localized: .favoritesRowCreature(favorite.number ?? 0)),
                label: String(localized: GameKind.exquisiteCorpse.name),
                date: favorite.occurredAt,
                destination: .exquisiteCorpseFigure(id)
            )
        case .storyChainStory:
            let untitled = String(localized: .favoritesRowStory(favorite.number ?? 0))
            return SearchResult(
                kind: .storyChain,
                key: id,
                title: favorite.title.flatMap { $0.isEmpty ? nil : $0 } ?? untitled,
                label: String(localized: GameKind.storyChain.name),
                date: favorite.occurredAt,
                destination: .storyChain(id)
            )
        default:
            return nil
        }
    }

    /// What an answer says: its words, else the option or partner it picked, else the kind of media.
    private static func answerText(of favorite: FavoriteSummary, people: StoryPeople, locale: Locale) -> String? {
        if let text = favorite.answerText, !text.isEmpty { return text }
        if let option = favorite.option(for: locale) { return option }
        if let name = people.name(ofUser: favorite.selectedUserID) { return name }
        switch favorite.mediaKind {
        case "photo": return String(localized: .dailyChallengeKindPhoto)
        case "voice": return String(localized: .dailyChallengeKindVoice)
        default: return nil
        }
    }
}

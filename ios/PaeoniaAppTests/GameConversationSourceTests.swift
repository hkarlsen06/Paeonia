import ExyteChat
import Foundation
import Testing

@testable import PaeoniaApp

struct GameConversationSourceTests {
    @Test func everyGameSourceSurvivesTheOutboxAndCache() throws {
        let id = UUID()
        let sources: [GameConversationSource] = [
            .mindMeld(id), .drawAndGuess(id), .consensio(id), .guessMySpot(id), .storyChain(id), .exquisiteCorpse(id),
            .connectFour(coupleID: id, number: 1), .dotsAndBoxes(coupleID: id, number: 1),
            .ultimateTicTacToe(coupleID: id, number: 1), .ludo(coupleID: id, number: 1),
        ]
        for source in sources {
            let game = GameChatSubject(coupleID: id, kind: source.kind)
            let subject = ThreadChatSubject.game(game)
            let data = try JSONEncoder().encode(subject)
            #expect(try JSONDecoder().decode(ThreadChatSubject.self, from: data) == subject)
            #expect(subject.id == game.id)
        }
    }

    @Test func boardSubjectIDMatchesTheServerAndSeparatesCouplesAndGames() throws {
        let coupleID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let source = GameConversationSource.ludo(coupleID: coupleID, number: 7)
        #expect(source.id.uuidString.lowercased() == "0a5acf9e-861c-3e27-12da-85c9e7b1ec89")
        #expect(source.id != GameConversationSource.ludo(coupleID: coupleID, number: 8).id)
        #expect(source.id != GameConversationSource.connectFour(coupleID: coupleID, number: 7).id)
        #expect(source.id != GameConversationSource.ludo(coupleID: UUID(), number: 7).id)
    }

    @Test func gameNotificationOpensTheSameConversationAndCanReply() throws {
        let coupleID = UUID()
        let url = try #require(URL(string: "paeonia://daily/game-chat?kind=mind_meld"))
        #expect(PaeoniaDeepLink(url) == .gameChat(kind: .mindMeld))
        let push = NotificationQuickActionPush(userInfo: [
            "type": "thread_message_sent", "couple_id": coupleID.uuidString,
            "thread_id": UUID().uuidString, "message_id": UUID().uuidString,
            "game_kind": "mind_meld",
        ])
        #expect(push.chatSubject == .game(GameChatSubject(coupleID: coupleID, kind: .mindMeld)))
        let invalid = try #require(URL(string: "paeonia://daily/game-chat?kind=unknown"))
        #expect(PaeoniaDeepLink(invalid) == nil)
    }

    @Test func persistentSubjectMatchesServerAndSeparatesKindsAndCouples() throws {
        let coupleID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let subject = GameChatSubject(coupleID: coupleID, kind: .connectFour)
        #expect(subject.id.uuidString.lowercased() == "5117096c-484e-52e5-c36f-bb03b8cfaad8")
        #expect(subject.id != GameChatSubject(coupleID: coupleID, kind: .ludo).id)
        #expect(subject.id != GameChatSubject(coupleID: UUID(), kind: .connectFour).id)
    }

    @MainActor
    @Test func savedGameContextPersistsAndCannotReturnAfterAPrivacyPurge() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileThreadChatCache(directoryURL: directory)
        let owner = UUID()
        let source = GameConversationSource.mindMeld(UUID())
        let result = GameConversationResult.mindMeld(
            RemoteMindMeldHistoryGame(
                id: source.id, gameNumber: 1, state: .melded, endReason: nil, endedByUserID: nil,
                createdAt: .distantPast, endedAt: .distantPast, meldNumber: 1,
                rounds: [
                    .init(roundNumber: 1, myWord: "Fish", partnerWord: "Fish", outcome: .match, countedByUserID: nil)
                ]
            ))
        let generation = await cache.purgeGeneration()
        #expect(
            await cache.saveGameResult(result, ownerUserID: owner, subjectID: source.id, unlessPurgedSince: generation))
        let reopened = FileThreadChatCache(directoryURL: directory)
        #expect(await reopened.gameResult(ownerUserID: owner, subjectID: source.id) == result)
        await cache.clearAll()
        #expect(
            await cache.saveGameResult(result, ownerUserID: owner, subjectID: source.id, unlessPurgedSince: generation)
                == false)
        #expect(
            await FileThreadChatCache(directoryURL: directory).gameResult(ownerUserID: owner, subjectID: source.id)
                == nil)
    }

    @MainActor
    @Test func expandingTheResultRedrawsItsExistingRowAndDoesNotCreateAMessage() throws {
        let source = GameConversationSource.mindMeld(UUID())
        let reference = GameChatResultReference(
            source: source, finishedAt: .now, key: source.id.uuidString.lowercased())
        func projection(expanded: Bool) -> ThreadChatProjection {
            ThreadChatProjection.make(input: .init(
                rounds: [], messages: [], currentUserID: UUID(), partnerName: "Robin", youName: "You",
                gameResults: [GameChatResultCard(reference: reference, result: nil,
                                                isExpanded: expanded, loadState: .loading)]))
        }
        let earlier = try #require(projection(expanded: false).exyteMessages.first)
        let later = try #require(projection(expanded: true).exyteMessages.first)
        #expect(earlier.id == later.id)
        #expect(earlier.triggerRedraw != later.triggerRedraw)
        #expect(projection(expanded: true).rowsByID.values.allSatisfy { $0.message == nil })
    }

    @Test func boardSourceRefusesAnInvalidGameNumber() {
        let json = Data(#"{"kind":"ludo","couple_id":"11111111-1111-1111-1111-111111111111","game_number":0}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GameConversationSource.self, from: json)
        }
    }
}

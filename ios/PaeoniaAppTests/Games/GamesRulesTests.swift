import Foundation
import Testing
@testable import PaeoniaApp

/// The Games rules that need no screen: what the server's JSON means, who counts
/// as here, when the invite button is back, and which phase a state is in.
struct GamesRulesTests {
    // MARK: Contract

    @Test func decodesTheDrawAndGuessQueryAsTheServerSendsIt() throws {
        let json = """
        {"user_id":"11111111-1111-1111-1111-111111111111","partner_user_id":"22222222-2222-2222-2222-222222222222",
         "couple_id":"33333333-3333-3333-3333-333333333333",
         "settings":{"couple_id":"33333333-3333-3333-3333-333333333333","play_style":"together","language":"nb",
           "updated_by_user_id":"22222222-2222-2222-2222-222222222222",
           "created_at":"2026-10-12T10:00:00.000Z","updated_at":"2026-10-12T10:00:00.000Z"},
         "game":{"id":"aaaaaaaa-0000-4000-8000-000000000001","kind":"draw_and_guess","state":"choosing_word",
           "turn_user_id":"11111111-1111-1111-1111-111111111111","turn_number":2,"current_round_id":null,
           "shared_points":5,"my_points":3,"partner_points":2,"turn_started_at":"2026-10-12T10:00:00.000Z",
           "version":4,"created_at":"2026-10-12T10:00:00.000Z","updated_at":"2026-10-12T10:00:00.000Z"},
         "current_round":null,"recent_rounds":[],
         "choices":[{"difficulty":"easy","word_id":"nb-easy-hund","word":"hund","points":1}],
         "my_last_seen_at":null,"partner_last_seen_at":"2026-10-12T10:00:30.500Z","last_invite_at":null}
        """
        let state = try PaeoniaConvexClient.decoder.decode(RemoteDrawAndGuessState.self, from: Data(json.utf8))

        #expect(state.settings?.playStyle == .together)
        #expect(state.settings?.language == .nb)
        #expect(state.game?.state == .choosingWord)
        #expect(state.game?.currentRoundID == nil)
        #expect(state.choices?.first?.wordID == "nb-easy-hund")
        #expect(state.partnerLastSeenAt != nil)
        #expect(state.currentRound == nil)
    }

    @Test func decodesARoundWithItsGuesses() throws {
        let json = """
        {"id":"bbbbbbbb-0000-4000-8000-000000000001","round_number":3,
         "drawer_user_id":"22222222-2222-2222-2222-222222222222","guesser_user_id":"11111111-1111-1111-1111-111111111111",
         "state":"solved","difficulty":"custom","word":"the dog","points":2,
         "drawing_media_asset_id":"cccccccc-0000-4000-8000-000000000001","drawing_submitted_at":"2026-10-12T10:00:00.000Z",
         "started_at":"2026-10-12T09:50:00.000Z","guesser_first_seen_at":"2026-10-12T10:00:05.000Z",
         "ended_at":"2026-10-12T10:00:20.000Z","solve_ms":15000,"speed_bonus":1,"memory_id":null,"saved_by_user_id":null,
         "my_save_response":"not_now","partner_save_response":null,
         "attempts":[{"id":"dddddddd-0000-4000-8000-000000000001","user_id":"11111111-1111-1111-1111-111111111111",
                      "text":"the cat","correct":false,"created_at":"2026-10-12T10:00:10.000Z"}]}
        """
        let round = try PaeoniaConvexClient.decoder.decode(RemoteDrawAndGuessRound.self, from: Data(json.utf8))

        #expect(round.difficulty == .custom)
        #expect(round.solveMs == 15_000)
        #expect(round.mySaveResponse == .notNow)
        #expect(round.partnerSaveResponse == nil)
        #expect(round.attempts.map(\.text) == ["the cat"])
    }

    // MARK: Presence and invite

    @Test func aHeartbeatUnderSixtySecondsOldCountsAsHere() {
        let now = GameFixture.now
        #expect(GamePresence.isFresh(now.addingTimeInterval(-59), now: now))
        #expect(!GamePresence.isFresh(now.addingTimeInterval(-60), now: now))
        #expect(!GamePresence.isFresh(nil, now: now))
        // A partner's clock a little ahead of this phone's is still fresh.
        #expect(GamePresence.isFresh(now.addingTimeInterval(5), now: now))
    }

    @Test func theInviteButtonIsHiddenWhenThePartnerIsHereAndSentForFifteenMinutes() {
        let now = GameFixture.now
        let sentRecently = now.addingTimeInterval(-14 * 60)

        #expect(GameInviteState.make(lastInviteAt: nil, partnerIsHere: true, now: now) == .hidden)
        #expect(GameInviteState.make(lastInviteAt: nil, partnerIsHere: false, now: now) == .available)
        #expect(
            GameInviteState.make(lastInviteAt: sentRecently, partnerIsHere: false, now: now)
                == .sent(until: sentRecently.addingTimeInterval(15 * 60))
        )
        #expect(
            GameInviteState.make(lastInviteAt: now.addingTimeInterval(-15 * 60), partnerIsHere: false, now: now)
                == .available
        )
    }

    @Test func anInviteSentFromThisPhoneCountsBeforeTheServerCatchesUp() {
        let now = GameFixture.now
        let state = GameInviteState.make(
            lastInviteAt: now.addingTimeInterval(-3_600),
            localSentAt: now,
            partnerIsHere: false,
            now: now
        )
        #expect(state == .sent(until: now.addingTimeInterval(15 * 60)))
    }

    // MARK: Score

    @Test func theScoreFollowsThePlayStyle() {
        let game = GameFixture.game(state: .choosingWord, turn: GameFixture.me)

        #expect(DrawAndGuessScore(game: game, playStyle: .together) == .together(total: 13))
        #expect(DrawAndGuessScore(game: game, playStyle: .against) == .against(mine: 8, partner: 5))
        #expect(DrawAndGuessScore(game: game, playStyle: .against).leader == .me)
        #expect(DrawAndGuessScore(game: game, playStyle: .together).leader == nil)
    }

    // MARK: Save prompt

    @Test func theSavePromptFollowsTheRulesFromTheDesign() {
        let me = GameFixture.me
        func prompt(
            _ round: RemoteDrawAndGuessRound,
            queued: Bool = false,
            hasDrawing: Bool = true
        ) -> DrawAndGuessSavePrompt {
            DrawAndGuessSavePrompt.make(
                round: DrawAndGuessRoundView(round),
                userID: me,
                hasSaveQueued: queued,
                hasDrawing: hasDrawing
            )
        }
        let solved = GameFixture.round(state: .solved, drawer: GameFixture.partner, hasDrawing: true)

        #expect(prompt(solved) == .ask)
        #expect(prompt(GameFixture.round(state: .guessing, drawer: GameFixture.partner)) == .hidden)
        #expect(prompt(solved, queued: true) == .saving)
        #expect(prompt(solved, hasDrawing: false) == .hidden)
        // "Not now" closes it for this person only.
        let notNow = GameFixture.round(
            state: .missed,
            drawer: GameFixture.partner,
            hasDrawing: true,
            mySaveResponse: .notNow
        )
        #expect(prompt(notNow) == .hidden)
    }

    @Test func aSavedRoundTurnsThePromptIntoSavedToMemories() throws {
        let json = """
        {"id":"bbbbbbbb-0000-4000-8000-000000000001","round_number":1,
         "drawer_user_id":"22222222-2222-2222-2222-222222222222","guesser_user_id":"11111111-1111-1111-1111-111111111111",
         "state":"solved","difficulty":"easy","word":"cat","points":1,"drawing_media_asset_id":null,
         "drawing_submitted_at":null,"started_at":"2026-10-12T09:50:00.000Z","guesser_first_seen_at":null,
         "ended_at":null,"solve_ms":null,"speed_bonus":0,
         "memory_id":"eeeeeeee-0000-4000-8000-000000000001","saved_by_user_id":"22222222-2222-2222-2222-222222222222",
         "my_save_response":null,"partner_save_response":null,"attempts":[]}
        """
        let round = try PaeoniaConvexClient.decoder.decode(RemoteDrawAndGuessRound.self, from: Data(json.utf8))

        let byPartner = DrawAndGuessSavePrompt.make(
            round: DrawAndGuessRoundView(round),
            userID: GameFixture.me,
            hasSaveQueued: false,
            hasDrawing: true
        )
        let byMe = DrawAndGuessSavePrompt.make(
            round: DrawAndGuessRoundView(round),
            userID: GameFixture.partner,
            hasSaveQueued: false,
            hasDrawing: true
        )

        #expect(byPartner == .savedByPartner)
        #expect(byMe == .saved)
    }

    // MARK: Language

    @Test func theGameLanguageDefaultsToTheFirstSupportedPhoneLanguage() {
        #expect(GameLanguage.preferred(from: ["nb-NO", "en-US"]) == .nb)
        #expect(GameLanguage.preferred(from: ["fr-FR", "en-GB"]) == .en)
        #expect(GameLanguage.preferred(from: ["no"]) == .nb)
        #expect(GameLanguage.preferred(from: ["de-DE"]) == .en)
    }

    // MARK: Deep link and notification setting

    @Test func theGamesLinkOpensDrawAndGuess() {
        #expect(PaeoniaDeepLink(PaeoniaDeepLink.drawAndGuessURL) == .drawAndGuess)
        #expect(PaeoniaDeepLink(URL(string: "paeonia://games/draw-and-guess")!) == .drawAndGuess)
        #expect(PaeoniaDeepLink(URL(string: "paeonia://games/other")!) == nil)
        let push: [AnyHashable: Any] = ["deeplink": "paeonia://games/draw-and-guess", "type": "game_turn_ready"]
        #expect(PaeoniaDeepLink(notificationUserInfo: push) == .drawAndGuess)
    }

    @Test func theGamesSwitchUsesTheGamesEnabledColumn() {
        #expect(NotificationPreferenceKind.games.columnName == "games_enabled")
        var preferences = NotificationPreferences()
        #expect(preferences[.games])
        preferences[.games] = false
        #expect(!preferences.gamesEnabled)
    }

    @Test func gamesSitsBetweenQuestionsAndMemoriesInTheTabBar() {
        #expect(MainTab.allCases == [.home, .questions, .games, .memories, .you])
    }
}

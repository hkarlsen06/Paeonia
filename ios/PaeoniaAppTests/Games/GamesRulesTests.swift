import Foundation
import Testing
@testable import PaeoniaApp

/// The Games rules that need no screen: what the server's JSON means, who counts
/// as here, and when the invite button is back.
@MainActor
struct GamesRulesTests {
    // MARK: Contract

    @Test func decodesTheDrawAndGuessQueryAsTheServerSendsIt() throws {
        let json = """
        {"user_id":"11111111-1111-1111-1111-111111111111","partner_user_id":"22222222-2222-2222-2222-222222222222",
         "couple_id":"33333333-3333-3333-3333-333333333333","data_epoch":"",
         "settings":{"couple_id":"33333333-3333-3333-3333-333333333333","play_style":"together","language":"nb",
           "updated_by_user_id":"22222222-2222-2222-2222-222222222222",
           "created_at":"2026-10-12T10:00:00.000Z","updated_at":"2026-10-12T10:00:00.000Z"},
         "game":{"id":"aaaaaaaa-0000-4000-8000-000000000001","kind":"draw_and_guess","state":"choosing_word",
           "turn_user_id":"11111111-1111-1111-1111-111111111111","turn_number":2,"current_round_id":null,
           "shared_points":5,"my_points":3,"partner_points":2,"turn_started_at":"2026-10-12T10:00:00.000Z",
           "version":4,"created_at":"2026-10-12T10:00:00.000Z","updated_at":"2026-10-12T10:00:00.000Z"},
         "current_round":null,"recent_rounds":[],
         "choices":[{"difficulty":"easy","word_id":"nb-easy-hund","word":"hund","points":1}],
         "my_present":false,"partner_present":true,"last_invite_at":null}
        """
        let state = try PaeoniaConvexClient.decoder.decode(RemoteDrawAndGuessState.self, from: Data(json.utf8))

        #expect(state.settings?.playStyle == .together)
        #expect(state.settings?.language == .nb)
        #expect(state.game?.state == .choosingWord)
        #expect(state.game?.currentRoundID == nil)
        #expect(state.choices?.first?.wordID == "nb-easy-hund")
        #expect(state.partnerPresent)
        #expect(state.currentRound == nil)
    }

    @Test func decodesARoundWithItsGuesses() throws {
        let json = """
        {"id":"bbbbbbbb-0000-4000-8000-000000000001","round_number":3,
         "drawer_user_id":"22222222-2222-2222-2222-222222222222",
         "guesser_user_id":"11111111-1111-1111-1111-111111111111",
         "state":"solved","difficulty":"custom","word":"the dog","points":2,
         "drawing_media_asset_id":"cccccccc-0000-4000-8000-000000000001",
         "drawing_submitted_at":"2026-10-12T10:00:00.000Z",
         "started_at":"2026-10-12T09:50:00.000Z","guesser_first_seen_at":"2026-10-12T10:00:05.000Z",
         "ended_at":"2026-10-12T10:00:20.000Z","solve_ms":15000,"speed_bonus":1,"first_try_bonus":0,
         "hints_used":2,"personal_best":false,"guesser_reaction":"laugh",
         "drawer_result_seen_at":null,"guesser_result_seen_at":"2026-10-12T10:00:30.000Z",
         "attempt_count":1,"starred_by_me":false,
         "attempts":[{"id":"dddddddd-0000-4000-8000-000000000001","user_id":"11111111-1111-1111-1111-111111111111",
                      "text":"the cat","correct":false,"created_at":"2026-10-12T10:00:10.000Z"}]}
        """
        let round = try PaeoniaConvexClient.decoder.decode(RemoteDrawAndGuessRound.self, from: Data(json.utf8))

        #expect(round.difficulty == .custom)
        #expect(round.solveMs == 15_000)
        #expect(round.speedBonus == 1)
        #expect(round.firstTryBonus == 0)
        #expect(round.hintsUsed == 2)
        #expect(!round.personalBest)
        #expect(round.guesserReaction == .laugh)
        #expect(round.drawerResultSeenAt == nil)
        #expect(round.guesserResultSeenAt != nil)
        #expect(round.attempts.map(\.text) == ["the cat"])
    }

    // MARK: Presence and invite

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

    // MARK: Language

    @Test func theGameLanguageDefaultsToTheFirstSupportedPhoneLanguage() {
        #expect(GameLanguage.preferred(from: ["nb-NO", "en-US"]) == .nb)
        #expect(GameLanguage.preferred(from: ["fr-FR", "en-GB"]) == .en)
        #expect(GameLanguage.preferred(from: ["no"]) == .nb)
        #expect(GameLanguage.preferred(from: ["de-DE"]) == .en)
    }

    @Test func theGuesserIsToldTheWordLanguageOnlyWhenItDiffersFromTheApp() {
        #expect(GameLanguage.guessNotice(game: .en, app: .nb, difficulty: .easy) == .en)
        #expect(GameLanguage.guessNotice(game: .nb, app: .en, difficulty: .hard) == .nb)
        #expect(GameLanguage.guessNotice(game: .nb, app: .nb, difficulty: .medium) == nil)
        // The drawer typed a custom word in any language.
        #expect(GameLanguage.guessNotice(game: .en, app: .nb, difficulty: .custom) == nil)
    }

    // MARK: Deep link and notification setting

    @Test func everyGameHasALinkThatOpensIt() {
        for kind in GameKind.allCases {
            #expect(PaeoniaDeepLink(PaeoniaDeepLink.gameURL(kind)) == .game(kind))
        }
        #expect(PaeoniaDeepLink.gameURL(.ultimateTicTacToe).absoluteString == "paeonia://games/ultimate-tic-tac-toe")
        #expect(PaeoniaDeepLink.gameURL(.ludo).absoluteString == "paeonia://games/ludo")
        #expect(PaeoniaDeepLink(URL(string: "paeonia://games/draw-and-guess")!) == .game(.drawAndGuess))
        #expect(PaeoniaDeepLink(URL(string: "paeonia://games/draw_and_guess")!) == nil)
        #expect(PaeoniaDeepLink(URL(string: "paeonia://games/other")!) == nil)
        let push: [AnyHashable: Any] = ["deeplink": "paeonia://games/mind-meld", "type": "game_turn_ready"]
        #expect(PaeoniaDeepLink(notificationUserInfo: push) == .game(.mindMeld))
    }
}

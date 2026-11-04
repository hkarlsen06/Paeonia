import Foundation
import Testing

@testable import PaeoniaApp

@MainActor
struct PiccanteRulesTests {
    @Test func sniffPreservesLiftedChocolateUntilTheTurnChanges() throws {
        let game = try #require(DeveloperPiccanteFixture.state(for: .piccanteBiting).game)
        var sniffed = game
        sniffed.version += 1
        sniffed.mySniff = PiccanteSniff(tile: 6, hasChili: false)
        #expect(PiccanteRules.keepsSelection(from: game, to: sniffed))
        sniffed.turnUserID = DeveloperGamesFixture.partner
        #expect(!PiccanteRules.keepsSelection(from: game, to: sniffed))
    }

    @Test func ownChiliMayBeBittenButNotSniffed() throws {
        let game = try #require(DeveloperPiccanteFixture.state(for: .piccanteBiting).game)
        let user = DeveloperGamesFixture.me
        let chili = try #require(game.myChili)
        #expect(PiccanteRules.canBite(chili, in: game, userID: user))
        #expect(!PiccanteRules.canSniff(chili, in: game, userID: user))
        #expect(PiccanteRules.canSniff(6, in: game, userID: user))
    }

    @Test func eatenSquaresAndOtherTurnsAreIllegal() throws {
        var game = try #require(DeveloperPiccanteFixture.state(for: .piccanteBiting).game)
        let user = DeveloperGamesFixture.me
        #expect(!PiccanteRules.canBite(0, in: game, userID: user))
        #expect(!PiccanteRules.canBite(-1, in: game, userID: user))
        #expect(!PiccanteRules.canBite(16, in: game, userID: user))
        game.turnUserID = DeveloperGamesFixture.partner
        #expect(!PiccanteRules.canBite(6, in: game, userID: user))
        game.turnUserID = user
        game.phase = .hiding
        #expect(!PiccanteRules.canBite(6, in: game, userID: user))
    }

    @Test func sniffCanOnlyBeUsedOnce() throws {
        let game = try #require(DeveloperPiccanteFixture.state(for: .piccanteSniff).game)
        #expect(!PiccanteRules.canSniff(8, in: game, userID: DeveloperGamesFixture.me))
        #expect(PiccanteRules.canBite(8, in: game, userID: DeveloperGamesFixture.me))
    }

    @Test func noteUsesScalarsAndRefusesControls() {
        #expect(PiccanteRules.validNote(String(repeating: "é", count: 60)))
        #expect(!PiccanteRules.validNote(String(repeating: "e\u{301}", count: 31)))
        #expect(!PiccanteRules.validNote("A\tB"))
        #expect(!PiccanteRules.validNote("A\u{2028}B"))
        #expect(!PiccanteRules.validNote("A\nB"))
        #expect(PiccanteRules.validNote("\n A kiss \n"))
    }

    @Test func noteInputCapsUnicodeScalarsAndRemovesLineBreaks() {
        let note = PiccanteRules.cappedNote(String(repeating: "e\u{301}", count: 40))
        #expect(note.unicodeScalars.count == 60)
        #expect(PiccanteRules.validNote(note))
        #expect(PiccanteRules.cappedNote("A\nB\tC") == "ABC")
    }

    @Test(arguments: [3, 4, 5]) func illustratedVarietiesKeepDistinctNeighbors(size: Int) {
        let id = DeveloperGamesFixture.gameID
        for tile in 0..<(size * size) {
            let variety = PiccanteRules.variety(gameID: id, number: 1, tile: tile)
            if tile % size + 1 < size {
                #expect(variety != PiccanteRules.variety(gameID: id, number: 1, tile: tile + 1))
            }
            if tile + size < size * size {
                #expect(variety != PiccanteRules.variety(gameID: id, number: 1, tile: tile + size))
            }
        }
    }

    @Test func restoreEpochAcceptsLowerVersions() {
        let old = DeveloperPiccanteFixture.state(for: .piccanteResult)
        var lower = DeveloperPiccanteFixture.state(for: .piccanteBiting)
        #expect(lower.isOlder(than: old))
        lower = RemotePiccanteState(
            userID: lower.userID, coupleID: lower.coupleID, partnerUserID: lower.partnerUserID,
            dataEpoch: "restored", game: lower.game, unseenResult: nil)
        #expect(!lower.isOlder(than: old))
    }

    @Test func openGameWireNeverContainsPartnerSecrets() throws {
        let state = DeveloperPiccanteFixture.state(for: .piccanteBiting)
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RemotePiccanteState.self, from: encoded)
        #expect(decoded.game?.chilis.isEmpty == true)
        #expect(decoded.game?.myNote == "You owe me a back rub.")
        #expect(decoded.game?.myChili == 12)
    }
}

@MainActor
struct PiccanteResolverTests {
    @Test func offlineMissedEndingSeenThenSizeAndHideKeepVersionsInOrder() throws {
        let finished = DeveloperPiccanteFixture.state(for: .piccanteResult)
        var newGame = try #require(finished.game)
        let result = newGame
        newGame.gameNumber = 2
        newGame.version = 9
        newGame.phase = .choosing
        newGame.starterUserID = finished.userID
        newGame.turnUserID = finished.userID
        newGame.size = nil
        newGame.myChili = nil
        newGame.myNote = nil
        newGame.mySniff = nil
        newGame.partnerHidden = false
        newGame.partnerSniffUsed = false
        newGame.winnerUserID = nil
        newGame.loserUserID = nil
        newGame.finishedAt = nil
        newGame.bites = []
        newGame.chilis = []
        let state = RemotePiccanteState(
            userID: finished.userID, coupleID: finished.coupleID,
            partnerUserID: finished.partnerUserID, dataEpoch: finished.dataEpoch, game: newGame, unseenResult: result)
        let seen = PiccanteMove(action: .seen, gameID: newGame.id, gameNumber: 1, expectedVersion: 9)
        let size = PiccanteMove(action: .choose, gameID: newGame.id, gameNumber: 2, expectedVersion: 9, size: 3)
        let hide = PiccanteMove(action: .hide, gameID: newGame.id, gameNumber: 2, expectedVersion: 10, tile: 2)
        let resolution = PiccanteResolver.resolve(state: state, pending: [seen, size, hide], deferredResult: nil)
        #expect(resolution.game?.gameNumber == 2)
        #expect(resolution.game?.version == 11)
        #expect(resolution.game?.size == 3)
        #expect(resolution.game?.myChili == 2)
        #expect(resolution.game?.phase == .hiding)
    }

    @Test func eitherChooserOwnsTheQueuedHideAndRematchHasNoTurn() throws {
        var state = DeveloperPiccanteFixture.state(for: .piccanteChooseSecond)
        state.game?.turnUserID = nil
        let game = try #require(state.game)
        let choose = PiccanteMove(action: .choose, gameID: game.id, gameNumber: game.gameNumber,
                                  expectedVersion: game.version, size: 5)
        let chosen = PiccanteResolver.resolve(state: state, pending: [choose], deferredResult: nil)
        #expect(chosen.game?.starterUserID == state.userID)
        #expect(chosen.game?.turnUserID == state.userID)
        #expect(chosen.game?.phase == .hiding)
    }

    @Test func repeatedSeenWritesDoNotChangeRematchVersion() async throws {
        let state = DeveloperPiccanteFixture.state(for: .piccanteResult)
        let game = try #require(state.game)
        let seen = PiccanteMove(action: .seen, gameID: game.id, gameNumber: game.gameNumber,
                                expectedVersion: game.version)
        let rematch = PiccanteMove(action: .rematch, gameID: game.id, gameNumber: game.gameNumber,
                                   expectedVersion: game.version)
        let resolved = PiccanteResolver.resolve(state: state, pending: [seen, seen, rematch], deferredResult: nil)
        #expect(resolved.game?.gameNumber == game.gameNumber + 1)
        #expect(resolved.game?.version == game.version + 1)
        #expect(resolved.game?.phase == .choosing)
        #expect(resolved.game?.turnUserID == nil)
        let cache = InMemoryPiccanteCache(state: state)
        var seenState = state
        seenState.unseenResult = nil
        await cache.saveState(seenState, ownerUserID: state.userID)
        #expect(await cache.document(ownerUserID: state.userID).state == seenState)
    }

    @Test func queuedBiteDoesNotInventAnOutcome() throws {
        let state = DeveloperPiccanteFixture.state(for: .piccanteBiting)
        let game = try #require(state.game)
        let bite = PiccanteMove(
            action: .bite, gameID: game.id, gameNumber: game.gameNumber,
            expectedVersion: game.version, tile: 6)
        let resolution = PiccanteResolver.resolve(state: state, pending: [bite], deferredResult: nil)
        #expect(resolution.heldTile == 6)
        #expect(resolution.game?.bites == game.bites)
        #expect(resolution.game?.chilis.isEmpty == true)
        #expect(resolution.game?.winnerUserID == nil)
    }
}

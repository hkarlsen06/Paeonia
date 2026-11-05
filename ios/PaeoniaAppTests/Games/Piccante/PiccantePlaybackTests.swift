import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct PiccantePlaybackTests {
    @Test func differentPhoneClocksResolveToTheSameServerInstant() {
        let server = Date(timeIntervalSince1970: 1_000)
        let deadline = server.addingTimeInterval(1)
        for skew in [-120.0, 45.0] {
            let sent = server.addingTimeInterval(skew - 0.1)
            let received = server.addingTimeInterval(skew + 0.1)
            let clock = PiccantePlaybackClock(serverTime: server, sentAt: sent, receivedAt: received)
            let localDeadline = clock.localDate(for: deadline)
            #expect(abs(localDeadline.timeIntervalSince1970 - skew - deadline.timeIntervalSince1970) < 0.001)
            #expect(abs(PiccantePlayback.delay(until: localDeadline, now: received) - 0.9) < 0.001)
            #expect(PiccantePlayback.delay(until: localDeadline, now: localDeadline.addingTimeInterval(4)) == 0)
        }
    }

    @Test func bothPhonesWaitForTheConfirmedBiteDespiteDifferentArrivalTimes() async throws {
        var first = DeveloperPiccanteFixture.state(for: .piccanteBiting)
        first.game?.bites = []
        let second = RemotePiccanteState(
            userID: first.partnerUserID, coupleID: first.coupleID, partnerUserID: first.userID,
            dataEpoch: first.dataEpoch, game: first.game, unseenResult: nil)
        let firstCache = InMemoryPiccanteCache(state: first)
        let secondCache = InMemoryPiccanteCache(state: second)
        let firstModel = model(first, cache: firstCache)
        let secondModel = model(second, cache: secondCache)
        defer { firstModel.stop(markResultSeen: false); secondModel.stop(markResultSeen: false) }
        await firstModel.reload()
        await secondModel.reload()
        let deadline = Date().addingTimeInterval(0.8)
        let bite = PiccanteBite(tile: 6, userID: first.userID, playAt: deadline)
        for stateIndex in 0...1 {
            if stateIndex == 1 { try await Task.sleep(for: .seconds(0.15)) }
            var state = stateIndex == 0 ? first : second
            state.game?.bites = [bite]
            state.game?.version += 1
            state.game?.turnUserID = first.partnerUserID
            if stateIndex == 0 {
                await firstCache.saveState(state, ownerUserID: state.userID)
                await firstModel.reload()
            } else {
                await secondCache.saveState(state, ownerUserID: state.userID)
                await secondModel.reload()
            }
        }
        #expect(firstModel.shownBites == 0)
        #expect(secondModel.shownBites == 0)
        try await Task.sleep(for: .seconds(1))
        #expect(firstModel.shownBites == 1)
        #expect(secondModel.shownBites == 1)
        #expect(await firstCache.document(ownerUserID: first.userID).shown?.bites == 1)
        #expect(await secondCache.document(ownerUserID: second.userID).shown?.bites == 1)
        await firstModel.reload()
        await secondModel.reload()
        #expect(firstModel.replayTask == nil)
        #expect(secondModel.replayTask == nil)
    }

    @Test func missingClockKeepsHistoricalBitesSpacedAndReduceMotionKeepsLiveAudio() {
        let now = Date()
        let old = PiccanteBite(tile: 1, userID: UUID(), playAt: now.addingTimeInterval(-60))
        let first = PiccantePlayback.plan(bite: old, clock: nil, reduceMotion: false, now: now)
        let second = PiccantePlayback.plan(bite: old, clock: nil, reduceMotion: false, now: first.startsAt)
        #expect(first.startsAt > now)
        #expect(second.startsAt > first.startsAt)
        let live = PiccanteBite(tile: 2, userID: old.userID, playAt: now.addingTimeInterval(0.9))
        let clock = PiccantePlaybackClock(serverTime: now, sentAt: now, receivedAt: now)
        #expect(PiccantePlayback.plan(bite: live, clock: clock, reduceMotion: true, now: now).playsSound)
        #expect(!PiccantePlayback.plan(bite: old, clock: clock, reduceMotion: true, now: now).playsSound)
    }

    @Test func cachedBitesReplayWhileTheClockRequestIsStalled() async throws {
        let state = DeveloperPiccanteFixture.state(for: .piccanteBiting)
        let cache = InMemoryPiccanteCache(state: state)
        await cache.saveShown(.init(number: 1, bites: 0), ownerUserID: state.userID)
        let model = model(state, cache: cache)
        model.playbackClock = nil
        model.playbackClockTask = Task { try? await Task.sleep(for: .seconds(20)) }
        defer { model.stop(markResultSeen: false) }
        await model.reload()
        try await Task.sleep(for: .seconds(0.5))
        #expect(model.shownBites > 0)
    }

    private func model(_ state: RemotePiccanteState, cache: InMemoryPiccanteCache) -> PiccanteViewModel {
        var dependencies = GamesTestEnvironment(state: nil).dependencies()
        dependencies.piccanteCache = cache
        let model = PiccanteViewModel(dependencies: dependencies)
        model.configure(participants: GameParticipants(
            currentUserID: state.userID, coupleID: state.coupleID,
            partnerName: "Partner"))
        let now = Date()
        model.playbackClock = PiccantePlaybackClock(serverTime: now, sentAt: now, receivedAt: now)
        return model
    }
}

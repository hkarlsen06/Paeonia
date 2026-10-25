import Foundation
import PencilKit
import Testing
import UIKit
@testable import PaeoniaApp

struct WidgetLiveStrokeSyncTests {
    @Test func strokeKeySurvivesEncodingAndScaling() throws {
        let original = PKDrawing(strokes: [
            makeStroke(x: 10, createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000.123)),
            makeStroke(x: 60, createdAt: Date(timeIntervalSinceReferenceDate: 800_000_001.456), pointCount: 5),
        ])
        let decoded = try PKDrawing(data: original.dataRepresentation())
        let scaled = decoded.scaled(fromSide: 320, toSide: 402)

        let originalKeys = original.strokes.map(WidgetLiveStrokeSync.key(for:))
        #expect(decoded.strokes.map(WidgetLiveStrokeSync.key(for:)) == originalKeys)
        #expect(scaled.strokes.map(WidgetLiveStrokeSync.key(for:)) == originalKeys)
        #expect(Set(originalKeys).count == 2)
    }

    @Test func trackerSendsOnlyWhatChanged() {
        let first = makeStroke(x: 10, createdAt: Date(timeIntervalSinceReferenceDate: 1))
        let second = makeStroke(x: 60, createdAt: Date(timeIntervalSinceReferenceDate: 2))
        var tracker = WidgetLiveStrokeTracker()
        tracker.reset(to: PKDrawing(strokes: [first]))

        let added = tracker.changes(to: PKDrawing(strokes: [first, second]))
        #expect(added.upserts.map(WidgetLiveStrokeSync.key(for:)) == [WidgetLiveStrokeSync.key(for: second)])
        #expect(added.removals.isEmpty)

        #expect(tracker.changes(to: PKDrawing(strokes: [first, second])).isEmpty)

        var recolored = first
        recolored.ink = PKInk(.pen, color: .blue)
        let changed = tracker.changes(to: PKDrawing(strokes: [recolored, second]))
        #expect(changed.upserts.count == 1)
        #expect(changed.upserts.first?.ink.color == .blue)

        let removed = tracker.changes(to: PKDrawing(strokes: [recolored]))
        #expect(removed.upserts.isEmpty)
        #expect(removed.removals == [WidgetLiveStrokeSync.key(for: second)])
    }

    @Test func applyReplacesInPlaceAppendsAndRemoves() {
        let first = makeStroke(x: 10, createdAt: Date(timeIntervalSinceReferenceDate: 1))
        let second = makeStroke(x: 60, createdAt: Date(timeIntervalSinceReferenceDate: 2))
        let third = makeStroke(x: 110, createdAt: Date(timeIntervalSinceReferenceDate: 3))
        var recolored = first
        recolored.ink = PKInk(.pen, color: .blue)

        let merged = WidgetLiveStrokeSync.apply(
            upserts: [third, recolored],
            removals: [WidgetLiveStrokeSync.key(for: second)],
            to: PKDrawing(strokes: [first, second])
        )

        #expect(merged.strokes.map(WidgetLiveStrokeSync.key(for:))
            == [first, third].map(WidgetLiveStrokeSync.key(for:)))
        #expect(merged.strokes.first?.ink.color == .blue)
    }

    @Test func joiningTakesTheRoomAndKeepsOnlyUnsentStrokes() {
        let saved = makeStroke(x: 10, createdAt: Date(timeIntervalSinceReferenceDate: 1))
        let erasedInRoom = makeStroke(x: 60, createdAt: Date(timeIntervalSinceReferenceDate: 2))
        let roomStroke = makeStroke(x: 110, createdAt: Date(timeIntervalSinceReferenceDate: 3))
        let unsentHere = makeStroke(x: 160, createdAt: Date(timeIntervalSinceReferenceDate: 4))

        let result = WidgetLiveStrokeSync.join(
            room: [saved, roomStroke],
            local: PKDrawing(strokes: [saved, erasedInRoom, unsentHere]),
            savedKeys: Set([saved, erasedInRoom].map(WidgetLiveStrokeSync.key(for:))),
            drawnHereKeys: [WidgetLiveStrokeSync.key(for: unsentHere)]
        )

        // The stroke the partner erased stays gone. The unsent one is kept and shared.
        #expect(result.drawing.strokes.map(WidgetLiveStrokeSync.key(for:))
            == [saved, roomStroke, unsentHere].map(WidgetLiveStrokeSync.key(for:)))
        #expect(result.ownUnsent.map(WidgetLiveStrokeSync.key(for:)) == [WidgetLiveStrokeSync.key(for: unsentHere)])
        #expect(!result.hasOtherUnsentStrokes)
    }

    @Test func aStrokeThePartnerErasedWhileThisPhoneWasAwayIsNotSentBack() {
        let roomStroke = makeStroke(x: 110, createdAt: Date(timeIntervalSinceReferenceDate: 3))
        let erasedThere = makeStroke(x: 60, createdAt: Date(timeIntervalSinceReferenceDate: 2))
        let unsentHere = makeStroke(x: 160, createdAt: Date(timeIntervalSinceReferenceDate: 4))

        let result = WidgetLiveStrokeSync.join(
            room: [roomStroke],
            local: PKDrawing(strokes: [erasedThere, roomStroke, unsentHere]),
            savedKeys: [],
            drawnHereKeys: Set([erasedThere, unsentHere].map(WidgetLiveStrokeSync.key(for:))),
            roomRemovals: [WidgetLiveStrokeSync.key(for: erasedThere)]
        )

        #expect(result.drawing.strokes.map(WidgetLiveStrokeSync.key(for:))
            == [roomStroke, unsentHere].map(WidgetLiveStrokeSync.key(for:)))
        #expect(result.ownUnsent.map(WidgetLiveStrokeSync.key(for:)) == [WidgetLiveStrokeSync.key(for: unsentHere)])
        #expect(!result.hasOtherUnsentStrokes)
    }

    @Test func anOldDraftDoesNotJoinTheSharedCanvas() {
        let roomStroke = makeStroke(x: 110, createdAt: Date(timeIntervalSinceReferenceDate: 3))
        let oldDraftStroke = makeStroke(x: 160, createdAt: Date(timeIntervalSinceReferenceDate: 4))

        let result = WidgetLiveStrokeSync.join(
            room: [roomStroke],
            local: PKDrawing(strokes: [oldDraftStroke]),
            savedKeys: [],
            drawnHereKeys: []
        )

        #expect(result.drawing.strokes.map(WidgetLiveStrokeSync.key(for:))
            == [WidgetLiveStrokeSync.key(for: roomStroke)])
        #expect(result.ownUnsent.isEmpty)
        #expect(result.hasOtherUnsentStrokes)
    }
}

struct WidgetLivePlaybackTests {
    @Test func dropsFinishedStrokesThatNeverArrived() {
        var playback = WidgetLivePlayback()
        playback.receive(liveMessage(id: "a", points: [livePoint]), now: 0)
        playback.receive(liveMessage(id: "b", points: [livePoint]), now: 0)
        playback.end("a", now: 1)

        playback.prune(now: 1 + WidgetLivePlayback.endedLifetime + 0.1)
        #expect(playback.strokes.keys.sorted() == ["b"])

        playback.remove(["b"])
        #expect(playback.isEmpty)
    }

    @Test func ignoresMalformedStrokes() {
        var playback = WidgetLivePlayback()
        var noColor = liveMessage(id: "a", points: [livePoint])
        noColor.color = nil
        playback.receive(noColor, now: 0)
        var pencilKitInk = liveMessage(id: "c", points: [livePoint])
        pencilKitInk.ink = PKInk.InkType.pen.rawValue
        playback.receive(pencilKitInk, now: 0)
        var tooWide = liveMessage(id: "d", points: [livePoint])
        tooWide.width = 1_000
        playback.receive(tooWide, now: 0)
        var noSeed = liveMessage(id: "e", points: [livePoint])
        noSeed.seed = nil
        playback.receive(noSeed, now: 0)
        var unknownLineStyle = liveMessage(id: "f", points: [livePoint])
        unknownLineStyle.lineStyle = "wavy"
        playback.receive(unknownLineStyle, now: 0)
        playback.receive(liveMessage(id: "b", points: [[10, 10, 0]]), now: 0)
        #expect(playback.isEmpty)
    }

    /// The partner's preview is built from the same recipe as the stroke that
    /// lands on the sender's canvas, so nothing moves when the real one arrives.
    @Test func thePartnersPreviewIsTheSendersStrokeScaledToTheirCanvas() throws {
        let style = InkStyle(kind: .pencil, color: .red, width: 9, lineStyle: .dashed)
        let samples = (0..<12).map { index in
            InkSample(
                location: CGPoint(x: 20 + Double(index) * 7, y: 40 + Double(index % 3) * 5),
                timeOffset: Double(index) * 0.016,
                force: nil,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        var stroke = InkStroke(style: style, first: samples[0], seed: 42)
        stroke.append(Array(samples.dropFirst()))
        var outgoing = WidgetLiveOutgoingStroke(side: 320)
        let taken = outgoing.takeMessage(from: stroke, now: 0)
        let message = try #require(taken)
        let wire = try JSONDecoder().decode(WidgetLiveMessage.self, from: JSONEncoder().encode(message))

        var playback = WidgetLivePlayback()
        playback.receive(wire, now: 0)
        let preview = try #require(playback.pencilKitStrokes(at: 10, side: 640).first)
        let finished = PKDrawing(strokes: [stroke.pencilKitStroke()]).scaled(fromSide: 320, toSide: 640).strokes[0]

        #expect(preview.randomSeed == finished.randomSeed)
        #expect(preview.ink.inkType == finished.ink.inkType)
        #expect(preview.transform == finished.transform)
        #expect(preview.path.count == finished.path.count)
        let previewMask = try #require(preview.mask)
        let finishedMask = try #require(finished.mask)
        #expect(abs(previewMask.bounds.width - finishedMask.bounds.width) < 0.01)
        #expect(abs(previewMask.bounds.minX - finishedMask.bounds.minX) < 0.01)
        for (shown, real) in zip(preview.path, finished.path) {
            #expect(abs(shown.location.x - real.location.x) < 0.001)
            #expect(abs(shown.location.y - real.location.y) < 0.001)
            #expect(shown.size == real.size)
            #expect(shown.opacity == real.opacity)
        }
    }
}

struct WidgetLiveMessageTests {
    @Test func encodesOnlyTheFieldsThatAreSet() throws {
        let data = try JSONEncoder().encode(WidgetLiveMessage(type: .liveEnd, id: "a"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(object == ["type": "liveEnd", "id": "a"])

        let relay = try JSONDecoder().decode(WidgetLiveMessage.self, from: Data(#"{"type":"welcome","peers":1}"#.utf8))
        #expect(relay == WidgetLiveMessage(type: .welcome, peers: 1))
    }
}

private func makeStroke(x: CGFloat, createdAt: Date, pointCount: Int = 3) -> PKStroke {
    let points = (0..<pointCount).map { index in
        PKStrokePoint(
            location: CGPoint(x: x + CGFloat(index) * 10, y: 20),
            timeOffset: Double(index) * 0.01,
            size: CGSize(width: 4, height: 4),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: .pi / 2
        )
    }
    return PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: createdAt))
}

/// `[x, y, timeOffset, azimuth, altitude]`.
private let livePoint: [Double] = [10, 10, 0, 0, 1.571]

private func liveMessage(id: String, points: [[Double]]) -> WidgetLiveMessage {
    WidgetLiveMessage(
        type: .live,
        id: id,
        ink: InkKind.pen.rawValue,
        color: [1, 0, 0, 1],
        side: 320,
        points: points,
        width: 5,
        seed: 7,
        lineStyle: InkLineStyle.solid.rawValue
    )
}

struct WidgetLivePresenceTests {
    @Test func drawingWinsOverWatchingAndLeavingClearsIt() {
        var presence = WidgetLivePresence()
        presence.welcome(id: "me", peers: 2)
        // The relay counted the partner's sockets, but nobody said hello yet.
        #expect(presence.partnerActivity == .away)

        presence.hello(from: "home", role: .watching)
        #expect(presence.partnerActivity == .watching)
        presence.hello(from: "canvas", role: .drawing)
        #expect(presence.partnerActivity == .drawing)

        presence.left(id: "canvas")
        #expect(presence.partnerActivity == .watching)
        presence.left(id: "home")
        #expect(presence.partnerActivity == .away)
        #expect(presence.peerCount == 0)
    }

    @Test func gameRolesAreReportedAndTheBusiestOneWins() {
        var presence = WidgetLivePresence()
        presence.welcome(id: "me", peers: 5)

        presence.hello(from: "a", role: .present)
        #expect(presence.partnerActivity == .present)
        presence.hello(from: "b", role: .result)
        #expect(presence.partnerActivity == .result)
        presence.hello(from: "c", role: .choosing)
        #expect(presence.partnerActivity == .choosing)
        presence.hello(from: "d", role: .watching)
        #expect(presence.partnerActivity == .watching)
        presence.hello(from: "e", role: .drawing)
        #expect(presence.partnerActivity == .drawing)

        // Each socket that leaves hands the activity down the list.
        presence.left(id: "e")
        #expect(presence.partnerActivity == .watching)
        presence.left(id: "d")
        #expect(presence.partnerActivity == .choosing)
        presence.left(id: "c")
        #expect(presence.partnerActivity == .result)
        presence.left(id: "b")
        #expect(presence.partnerActivity == .present)
    }

    /// The partner's phone locked while they guessed, and the relay kept that
    /// socket. Back in the game on a new socket, they looked at the result, and
    /// the old socket's `watching` still won.
    @Test func inTheGameRoomAnOldSocketNeverOutranksTheLatestHello() {
        var presence = WidgetLivePresence(countsLatestHelloOnly: true)
        presence.welcome(id: "me", peers: 1)
        presence.hello(from: "old", role: .watching)
        presence.joined()
        presence.hello(from: "new", role: .result)
        #expect(presence.partnerActivity == .result)

        presence.left(id: "new")
        #expect(presence.partnerActivity == .away)

        presence.reset()
        presence.welcome(id: "me", peers: 2)
        presence.hello(from: "a", role: .drawing)
        presence.hello(from: "b", role: .present)
        #expect(presence.partnerActivity == .present)
    }

    @Test func aNewHelloFromTheSameSocketReplacesItsRole() {
        var presence = WidgetLivePresence()
        presence.welcome(id: "me", peers: 1)
        presence.hello(from: "phone", role: .result)
        #expect(presence.partnerActivity == .result)
        presence.hello(from: "phone", role: .watching)
        #expect(presence.partnerActivity == .watching)
    }

    @Test func joinedThenHelloCountsThePartner() {
        var presence = WidgetLivePresence()
        presence.welcome(id: "me", peers: 0)
        presence.joined()
        presence.hello(from: "canvas", role: .drawing)
        #expect(presence.partnerActivity == .drawing)
        #expect(presence.ownID == "me")
    }
}

struct WidgetLiveRoomTests {
    @Test func snapshotReplacesAndOpsFollow() {
        let first = makeStroke(x: 10, createdAt: Date(timeIntervalSinceReferenceDate: 1))
        let second = makeStroke(x: 60, createdAt: Date(timeIntervalSinceReferenceDate: 2))
        var room = WidgetLiveRoom()

        room.apply(WidgetLiveMessage(type: .ops, snapshot: true), upserts: [first])
        room.apply(WidgetLiveMessage(type: .ops), upserts: [second])
        #expect(room.drawing?.strokes.count == 2)

        room.apply(WidgetLiveMessage(type: .ops, removals: [WidgetLiveStrokeSync.key(for: first)]), upserts: [])
        #expect(room.drawing?.strokes.map(WidgetLiveStrokeSync.key(for:)) == [WidgetLiveStrokeSync.key(for: second)])

        // A new snapshot is the whole canvas, also when it is empty.
        room.apply(WidgetLiveMessage(type: .ops, snapshot: true), upserts: [])
        #expect(room.drawing?.strokes.isEmpty == true)
    }
}

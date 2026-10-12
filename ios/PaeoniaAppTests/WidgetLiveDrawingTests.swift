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
    @Test func revealsPointsAtTheirOwnPaceAfterTheDelay() throws {
        var playback = WidgetLivePlayback()
        playback.receive(liveMessage(id: "a", points: [[10, 10, 0, 0], [20, 10, 0.05, 0]]), now: 100)
        playback.receive(liveMessage(id: "a", points: [[30, 10, 0.1, 0]]), now: 100.1)

        #expect(playback.pencilKitStrokes(at: 100.05, side: 320).isEmpty)
        #expect(try #require(playback.pencilKitStrokes(at: 100.1, side: 320).first).path.count == 1)
        #expect(try #require(playback.pencilKitStrokes(at: 100.16, side: 320).first).path.count == 2)
        #expect(try #require(playback.pencilKitStrokes(at: 100.3, side: 320).first).path.count == 3)
    }

    @Test func scalesToThisCanvas() throws {
        var playback = WidgetLivePlayback()
        playback.receive(liveMessage(id: "a", points: [[100, 50, 0, 0]]), now: 0)

        let point = try #require(playback.pencilKitStrokes(at: 1, side: 640).first?.path.first)
        #expect(point.location == CGPoint(x: 200, y: 100))
        // The learned size, scaled with the canvas. Stroke points are stored
        // compressed, so compare loosely.
        #expect(abs(point.size.width - 8) < 0.1)
    }

    @Test func dropsFinishedStrokesThatNeverArrived() {
        var playback = WidgetLivePlayback()
        playback.receive(liveMessage(id: "a", points: [[10, 10, 0, 0]]), now: 0)
        playback.receive(liveMessage(id: "b", points: [[10, 10, 0, 0]]), now: 0)
        playback.end("a", now: 1)

        playback.prune(now: 1 + WidgetLivePlayback.endedLifetime + 0.1)
        #expect(playback.strokes.keys.sorted() == ["b"])

        playback.remove(["b"])
        #expect(playback.isEmpty)
    }

    @Test func ignoresMalformedStrokes() {
        var playback = WidgetLivePlayback()
        var noColor = liveMessage(id: "a", points: [[10, 10, 0, 0]])
        noColor.color = nil
        playback.receive(noColor, now: 0)
        var noStyle = liveMessage(id: "c", points: [[10, 10, 0, 0]])
        noStyle.pointStyle = nil
        playback.receive(noStyle, now: 0)
        playback.receive(liveMessage(id: "b", points: [[10, 10, 0]]), now: 0)
        #expect(playback.isEmpty)
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

private func liveMessage(id: String, points: [[Double]]) -> WidgetLiveMessage {
    WidgetLiveMessage(
        type: .live,
        id: id,
        ink: PKInk.InkType.pen.rawValue,
        color: [1, 0, 0, 1],
        side: 320,
        points: points,
        pointStyle: WidgetLiveInkCalibration.Style(width: 10, size: 4)
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

    @Test func scalesForTheViewAndBumpsTheVersion() throws {
        var room = WidgetLiveRoom()
        let startVersion = room.version
        room.apply(
            WidgetLiveMessage(type: .ops, snapshot: true),
            upserts: [makeStroke(x: 10, createdAt: Date(timeIntervalSinceReferenceDate: 1))]
        )
        #expect(room.version == startVersion + 1)

        let scaledBounds = PKDrawing(strokes: room.strokes(side: WidgetLiveRoom.side * 2)).bounds
        let originalBounds = try #require(room.drawing?.bounds)
        // The line moves and grows with the view. The ink width may not scale
        // exactly, so compare the centers.
        #expect(
            abs(scaledBounds.midX - originalBounds.midX * 2) < 1,
            "scaled \(scaledBounds), original \(originalBounds)"
        )

        room.clear()
        #expect(room.drawing == nil)
        #expect(room.strokes(side: 100).isEmpty)
    }
}

struct WidgetLiveInkCalibrationTests {
    private let pen = PKInk.InkType.pen.rawValue

    @Test func usesTheRealStrokeSizeNotTheToolWidth() throws {
        var calibration = WidgetLiveInkCalibration()
        #expect(calibration.style(ink: pen, width: 10) == nil)

        calibration.record(ink: pen, width: 10, stroke: makeSizedStroke(size: 3, force: 0.4))
        let style = try #require(calibration.style(ink: pen, width: 10))
        #expect(style.size == 3)
        #expect(abs(style.force - 0.4) < 0.0001)
        #expect(calibration.style(ink: PKInk.InkType.pencil.rawValue, width: 10) == nil)
    }

    @Test func interpolatesAndExtendsBetweenRecordedWidths() throws {
        var calibration = WidgetLiveInkCalibration()
        calibration.record(ink: pen, width: 2, stroke: makeSizedStroke(size: 2, force: 1))
        calibration.record(ink: pen, width: 22, stroke: makeSizedStroke(size: 6, force: 1))

        #expect(try #require(calibration.style(ink: pen, width: 12)).size == 4)
        // Beyond the largest width it follows the same slope.
        #expect(abs(try #require(calibration.style(ink: pen, width: 32)).size - 8) < 0.0001)
        // Below the smallest it never reaches zero, so the line stays visible.
        #expect(try #require(calibration.style(ink: pen, width: 0.5)).size > 0)
    }

    @Test func survivesSavingAndLoading() throws {
        let defaults = try #require(UserDefaults(suiteName: "WidgetLiveInkCalibrationTests"))
        defaults.removePersistentDomain(forName: "WidgetLiveInkCalibrationTests")
        var calibration = WidgetLiveInkCalibration()
        calibration.record(ink: pen, width: 10, stroke: makeSizedStroke(size: 3, force: 1))
        calibration.save(to: defaults)

        #expect(WidgetLiveInkCalibration.load(from: defaults) == calibration)
    }
}

private func makeSizedStroke(size: CGFloat, force: CGFloat) -> PKStroke {
    let points = (0..<5).map { index in
        PKStrokePoint(
            location: CGPoint(x: CGFloat(index) * 10, y: 20),
            timeOffset: Double(index) * 0.01,
            size: CGSize(width: size, height: size),
            opacity: 1,
            force: force,
            azimuth: 0,
            altitude: .pi / 2
        )
    }
    return PKStroke(ink: PKInk(.pen, color: .red), path: PKStrokePath(controlPoints: points, creationDate: Date()))
}

struct WidgetLiveInkCalibrationInputTests {
    @Test func fingerAndPencilAreLearnedApart() throws {
        let ink = PKInk.InkType.pen.rawValue
        let finger = WidgetLiveInkCalibration.key(ink: ink, isPencil: false)
        let pencil = WidgetLiveInkCalibration.key(ink: ink, isPencil: true)
        var calibration = WidgetLiveInkCalibration()
        calibration.record(ink: finger, width: 10, stroke: makeSizedStroke(size: 2, force: 1))
        calibration.record(ink: pencil, width: 10, stroke: makeSizedStroke(size: 7, force: 1))

        #expect(try #require(calibration.style(ink: finger, width: 10)).size == 2)
        #expect(try #require(calibration.style(ink: pencil, width: 10)).size == 7)
    }
}

struct WidgetLiveInkStyleTests {
    @Test func learnsEveryAttributeThatChangesTheLook() throws {
        let points = (0..<5).map { index in
            PKStrokePoint(
                location: CGPoint(x: CGFloat(index) * 10, y: 20),
                timeOffset: Double(index) * 0.01,
                size: CGSize(width: 6, height: 6),
                opacity: 1.6,
                force: 0.5,
                azimuth: 0,
                altitude: 1.2,
                secondaryScale: 1.4,
                threshold: 0
            )
        }
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .red),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
        var calibration = WidgetLiveInkCalibration()
        calibration.record(ink: "pen|finger", width: 3, stroke: stroke)

        let style = try #require(calibration.style(ink: "pen|finger", width: 3))
        let rebuilt = style.point(at: .zero, timeOffset: 0, azimuth: 0, scale: 1)
        // Stroke points are stored compressed, so compare loosely.
        #expect(abs(rebuilt.size.width - 6) < 0.1)
        #expect(abs(rebuilt.opacity - 1.6) < 0.05)
        #expect(abs(rebuilt.secondaryScale - 1.4) < 0.05)
        #expect(abs(rebuilt.altitude - 1.2) < 0.05)
    }
}

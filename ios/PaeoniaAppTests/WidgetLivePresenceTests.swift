import Testing
@testable import PaeoniaApp

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

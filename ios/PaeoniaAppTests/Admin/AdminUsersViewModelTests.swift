import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct AdminUsersViewModelTests {
    /// Collects the debounce waits, and can make them fail like a cancelled wait does.
    private actor SleepLog {
        private(set) var durations = [Duration]()
        let cancels: Bool

        init(cancels: Bool = false) {
            self.cancels = cancels
        }

        func record(_ duration: Duration) throws {
            durations.append(duration)
            if cancels {
                throw CancellationError()
            }
        }
    }

    private func makeModel(
        bannedOnly: Bool = false,
        gateway: AdminFakeGateway,
        sleepLog: SleepLog = SleepLog()
    ) -> AdminUsersViewModel {
        AdminUsersViewModel(
            bannedOnly: bannedOnly,
            gateway: gateway,
            sleep: { duration in try await sleepLog.record(duration) }
        )
    }

    @Test func firstLoadListsTheNewestUsersWithoutWaiting() async {
        let gateway = AdminFakeGateway(users: [AdminFixtures.summary(), AdminFixtures.summary()])
        let sleepLog = SleepLog()
        let model = makeModel(gateway: gateway, sleepLog: sleepLog)

        await model.search()

        #expect(model.users.count == 2)
        #expect(model.hasLoaded)
        #expect(gateway.searches == [AdminSearchCall(query: nil, bannedOnly: false)])
        #expect(await sleepLog.durations.isEmpty)
    }

    @Test func typingWaitsThreeHundredMillisecondsThenSearches() async {
        let gateway = AdminFakeGateway()
        let sleepLog = SleepLog()
        let model = makeModel(gateway: gateway, sleepLog: sleepLog)
        await model.search()

        model.searchText = "  ma "
        await model.search()

        #expect(await sleepLog.durations == [.milliseconds(300)])
        #expect(gateway.searches.last == AdminSearchCall(query: "ma", bannedOnly: false))
    }

    @Test func oneCharacterDoesNotSearch() async {
        let gateway = AdminFakeGateway()
        let model = makeModel(gateway: gateway)
        await model.search()

        model.searchText = "m"
        await model.search()

        #expect(model.isSearchTooShort)
        #expect(gateway.searches.count == 1)
    }

    @Test func clearingTheTextListsTheNewestUsersAgain() async {
        let gateway = AdminFakeGateway()
        let model = makeModel(gateway: gateway)
        await model.search()
        model.searchText = "maja"
        await model.search()

        model.searchText = ""
        await model.search()

        #expect(!model.isSearchTooShort)
        #expect(gateway.searches.last == AdminSearchCall(query: nil, bannedOnly: false))
    }

    @Test func aFullUserIDIsSentAsTheQuery() async {
        let gateway = AdminFakeGateway()
        let model = makeModel(gateway: gateway)
        await model.search()

        model.searchText = AdminFixtures.userID.uuidString
        await model.search()

        #expect(gateway.searches.last?.query == AdminFixtures.userID.uuidString)
    }

    @Test func aCancelledWaitNeverSearches() async {
        let gateway = AdminFakeGateway()
        let model = makeModel(gateway: gateway, sleepLog: SleepLog(cancels: true))
        await model.search()

        model.searchText = "maja"
        await model.search()

        #expect(gateway.searches.count == 1)
    }

    @Test func comingBackToTheSameTextReloadsWithoutWaiting() async {
        let gateway = AdminFakeGateway()
        let sleepLog = SleepLog()
        let model = makeModel(gateway: gateway, sleepLog: sleepLog)
        model.searchText = "maja"
        await model.search()

        await model.search()

        #expect(gateway.searches.count == 2)
        #expect(await sleepLog.durations.isEmpty)
    }

    @Test func bannedListAsksForBannedUsersAndIgnoresTheText() async {
        let gateway = AdminFakeGateway(users: [AdminFixtures.summary(bannedAt: AdminFixtures.bannedAt)])
        let model = makeModel(bannedOnly: true, gateway: gateway)
        model.searchText = "x"

        await model.search()

        #expect(!model.isSearchTooShort)
        #expect(model.users.count == 1)
        #expect(gateway.searches == [AdminSearchCall(query: nil, bannedOnly: true)])
    }

    @Test func aCancelledSearchDropsItsResult() async {
        let gateway = AdminFakeGateway(users: [AdminFixtures.summary()])
        let gate = AdminGate()
        gateway.holdSearches(with: gate)
        let model = makeModel(gateway: gateway)

        let task = Task { await model.search() }
        await waitUntil { await gate.isWaiting }
        task.cancel()
        await gate.open()
        await task.value

        #expect(model.users.isEmpty)
        #expect(!model.hasLoaded)
        #expect(model.notice == nil)
    }

    @Test func refreshKeepsTheCurrentSearch() async {
        let gateway = AdminFakeGateway()
        let model = makeModel(gateway: gateway)
        model.searchText = "maja"
        await model.search()

        gateway.setUsers([AdminFixtures.summary()])
        await model.refresh()

        #expect(gateway.searches.last == AdminSearchCall(query: "maja", bannedOnly: false))
        #expect(model.users.count == 1)
    }

    @Test func failedLoadRaisesANotice() async {
        let gateway = AdminFakeGateway(error: AdminFakeError.failed)
        let model = makeModel(gateway: gateway)

        await model.search()

        #expect(model.notice == .loadFailed)
        #expect(model.hasLoaded)
    }

    @Test func nonAdminErrorRaisesTheAccessNotice() async {
        let gateway = AdminFakeGateway(error: AdminFixtures.serverError("admin access required"))
        let model = makeModel(gateway: gateway)

        await model.search()

        #expect(model.notice == .notAdmin)
    }
}

private func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<200 where !(await condition()) {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

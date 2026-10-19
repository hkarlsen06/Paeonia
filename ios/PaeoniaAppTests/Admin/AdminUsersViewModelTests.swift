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

    @Test func aCancelledWaitNeverSearches() async {
        let gateway = AdminFakeGateway()
        let model = makeModel(gateway: gateway, sleepLog: SleepLog(cancels: true))
        await model.search()

        model.searchText = "maja"
        await model.search()

        #expect(gateway.searches.count == 1)
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
}

private func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<200 where !(await condition()) {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

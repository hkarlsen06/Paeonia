import Testing
@testable import PaeoniaApp

struct PaeoniaAppTests {

    @Test func testHarnessIsAvailable() {
        #expect(AppState.allCases.count == 6)
    }
}

import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct WidgetNudgeModelTests {
    @Test func drawingWidgetCountsAsInstalled() async {
        let configurations = WidgetNudgeFakeConfigurations([[LockScreenWidgetKind.streak, PaeoniaAppGroup.widgetKind]])

        #expect(await WidgetNudgeModel.isWidgetInstalled(configurations: configurations))
    }

    @Test func lockScreenWidgetsAloneDoNotCount() async {
        let configurations = WidgetNudgeFakeConfigurations([LockScreenWidgetKind.all])

        #expect(!(await WidgetNudgeModel.isWidgetInstalled(configurations: configurations)))
    }

    @Test func failedReadCountsAsNotInstalled() async {
        #expect(!(await WidgetNudgeModel.isWidgetInstalled(configurations: WidgetNudgeFailingConfigurations())))
    }

    @Test func checkFindsTheWidgetOnce() async {
        let configurations = WidgetNudgeFakeConfigurations([[PaeoniaAppGroup.widgetKind]])
        let model = WidgetNudgeModel(configurations: configurations, recheckDelay: .zero)

        let first = await model.check()
        let second = await model.check()

        #expect(first)
        #expect(!second)
        #expect(model.isAdded)
        // Once found, later checks don't ask WidgetKit again.
        #expect(await configurations.callCount == 1)
    }

    @Test func checkWithoutTheWidgetKeepsWaiting() async {
        let model = WidgetNudgeModel(configurations: WidgetNudgeFakeConfigurations([[]]), recheckDelay: .zero)

        #expect(!(await model.check()))
        #expect(!model.isAdded)
    }

    @Test func returningChecksAgainForAWidgetWidgetKitListsLate() async {
        let configurations = WidgetNudgeFakeConfigurations([[], [PaeoniaAppGroup.widgetKind]])
        let model = WidgetNudgeModel(configurations: configurations, recheckDelay: .zero)

        let found = await model.checkAfterReturning()

        #expect(found)
        #expect(model.isAdded)
        #expect(await configurations.callCount == 2)
    }

    @Test func returningWithoutTheWidgetChecksTwiceAndKeepsWaiting() async {
        let configurations = WidgetNudgeFakeConfigurations([[]])
        let model = WidgetNudgeModel(configurations: configurations, recheckDelay: .zero)

        #expect(!(await model.checkAfterReturning()))
        #expect(!model.isAdded)
        #expect(await configurations.callCount == 2)
    }
}

// MARK: - Test doubles

// swiftlint:disable async_without_await

/// Answers with each list in turn, then keeps repeating the last one.
actor WidgetNudgeFakeConfigurations {
    private var responses: [[String]]
    private(set) var callCount = 0

    init(_ responses: [[String]]) {
        self.responses = responses
    }

    func nextKinds() -> [String] {
        callCount += 1
        return responses.count > 1 ? responses.removeFirst() : responses.first ?? []
    }
}

extension WidgetNudgeFakeConfigurations: WidgetConfigurationProviding {
    func installedWidgetKinds() async throws -> [String] {
        nextKinds()
    }
}

struct WidgetNudgeFailingConfigurations: WidgetConfigurationProviding {
    func installedWidgetKinds() async throws -> [String] {
        throw URLError(.unknown)
    }
}

// swiftlint:enable async_without_await

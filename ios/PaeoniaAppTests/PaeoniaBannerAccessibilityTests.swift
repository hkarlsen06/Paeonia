import Foundation
import Testing
@testable import PaeoniaApp

@MainActor
struct PaeoniaBannerAccessibilityTests {
    @Test func rootHostDoesNotCoverTheFrontmostPresentation() {
        let center = PaeoniaBannerCenter()
        let root = UUID()
        let tabs = UUID()
        let sheet = UUID()
        center.registerHost(tabs)
        center.registerHost(sheet)
        center.registerHost(root, isRoot: true)
        #expect(center.isActiveHost(sheet))
        center.unregisterHost(sheet)
        #expect(center.isActiveHost(tabs))
        center.unregisterHost(tabs)
        #expect(center.isActiveHost(root))
    }

    @Test func errorRemainsUntilDismissedWithoutATimeLimit() async throws {
        let center = PaeoniaBannerCenter(infoDuration: .milliseconds(1), isVoiceOverRunning: { false })
        let error = PaeoniaBannerContent.error(message: "Could not save")
        center.show(error)
        try await Task.sleep(for: .milliseconds(40))
        #expect(center.content?.id == error.id)
        center.dismiss()
        #expect(center.content == nil)
    }

    @Test func actionableNoticeRemainsAvailableForSlowInput() async throws {
        let center = PaeoniaBannerCenter(infoDuration: .milliseconds(1), isVoiceOverRunning: { false })
        let notice = PaeoniaBannerContent.info(message: "Open the reply", isTappable: true)
        center.show(notice)
        try await Task.sleep(for: .milliseconds(40))
        #expect(center.content?.id == notice.id)
    }

    @Test func nonActionableNoticeStillDismisses() async throws {
        let center = PaeoniaBannerCenter(infoDuration: .milliseconds(1), isVoiceOverRunning: { false })
        center.show(.info(message: "Saved"))
        try await Task.sleep(for: .milliseconds(40))
        #expect(center.content == nil)
    }
}

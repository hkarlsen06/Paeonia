import Foundation
import Testing
@testable import PaeoniaApp

/// Covers the top banner's timer and dedupe rules. Durations are short and
/// injected; every wait leaves at least 150 ms of margin on both sides.
@MainActor
struct PaeoniaBannerCenterTests {
    private func makeCenter(
        errorDuration: Duration = .seconds(5),
        infoDuration: Duration = .seconds(5),
        isVoiceOverRunning: Bool = false
    ) -> PaeoniaBannerCenter {
        PaeoniaBannerCenter(
            errorDuration: errorDuration,
            infoDuration: infoDuration,
            isVoiceOverRunning: { isVoiceOverRunning }
        )
    }

    @Test func infoBannerClearsAfterTheInfoDuration() async throws {
        let center = makeCenter(errorDuration: .seconds(5), infoDuration: .milliseconds(100))

        center.show(.info(message: "Your partner drew something"))
        #expect(center.content != nil)

        try await Task.sleep(for: .milliseconds(500))
        #expect(center.content == nil)
    }

    @Test func errorBannerUsesTheErrorDuration() async throws {
        let center = makeCenter(errorDuration: .seconds(5), infoDuration: .milliseconds(100))

        center.show(.error(message: "Could not save"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(center.content != nil)

        center.dismiss()
        #expect(center.content == nil)
    }

    @Test func olderTimerDoesNotDismissNewerBanner() async throws {
        let center = makeCenter(errorDuration: .milliseconds(600))
        let first = PaeoniaBannerContent.error(message: "First")
        let second = PaeoniaBannerContent.error(message: "Second")

        center.show(first)
        try await Task.sleep(for: .milliseconds(400))
        center.show(second)

        // Past the first banner's deadline (600 ms), before the second's (1000 ms).
        try await Task.sleep(for: .milliseconds(400))
        #expect(center.content?.id == second.id)

        try await Task.sleep(for: .milliseconds(500))
        #expect(center.content == nil)
    }

    @Test func sameContentKeepsTheBannerAndRestartsItsTimer() async throws {
        let center = makeCenter(errorDuration: .milliseconds(600))
        let first = PaeoniaBannerContent.error(title: "Oops", message: "Could not save")

        center.show(first)
        try await Task.sleep(for: .milliseconds(400))
        center.show(.error(title: "Oops", message: "Could not save"))
        #expect(center.content?.id == first.id)

        // Past the original deadline (600 ms), before the restarted one (1000 ms).
        try await Task.sleep(for: .milliseconds(400))
        #expect(center.content?.id == first.id)

        try await Task.sleep(for: .milliseconds(500))
        #expect(center.content == nil)
    }

    @Test func differentTextOrStyleReplacesTheBanner() {
        let center = makeCenter()
        let first = PaeoniaBannerContent.error(message: "Could not save")
        let otherMessage = PaeoniaBannerContent.error(message: "Could not send")
        let otherStyle = PaeoniaBannerContent.info(message: "Could not send")

        center.show(first)
        center.show(otherMessage)
        #expect(center.content?.id == otherMessage.id)

        center.show(otherStyle)
        #expect(center.content?.id == otherStyle.id)
    }

    @Test func dismissWithStaleIdDoesNothing() {
        let center = makeCenter()
        let first = PaeoniaBannerContent.error(message: "First")
        let second = PaeoniaBannerContent.error(message: "Second")

        center.show(first)
        center.show(second)

        center.dismiss(id: first.id)
        #expect(center.content?.id == second.id)

        center.dismiss(id: second.id)
        #expect(center.content == nil)
    }

    @Test func staysUntilDismissedWhenVoiceOverIsRunning() async throws {
        let center = makeCenter(
            errorDuration: .milliseconds(100),
            infoDuration: .milliseconds(100),
            isVoiceOverRunning: true
        )

        center.show(.error(message: "Could not save"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(center.content != nil)

        center.dismiss()
        #expect(center.content == nil)
    }
}

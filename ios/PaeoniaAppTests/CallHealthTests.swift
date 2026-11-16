import Foundation
import Testing
@testable import PaeoniaApp

struct CallConnectionHealthTests {
    /// Builds samples every 2 seconds with 100 packets sent in each, like voice at 50 a second.
    private struct Feed {
        var health = CallConnectionHealth()
        var seconds = 0.0
        var sent = 0
        var lost = 0
        var videoBytes = 0
        /// A shared screen's packets in each sample, next to the voice's.
        var screenPackets = 0
        var screenSent = 0

        /// Adds one sample where `lossShare` of the new packets never reached the partner.
        /// Returns whether the verdict changed.
        @discardableResult
        mutating func add(
            lossShare: Double = 0,
            roundTrip: Double = 0.05,
            packets: Int = 100,
            videoLimitedTo available: Double? = nil,
            screenLimitedTo screenAvailable: Double? = nil
        ) -> Bool {
            seconds += 2
            sent += packets
            screenSent += screenPackets
            lost += Int((Double(packets + screenPackets) * lossShare).rounded())
            var sample = CallStatsSample(seconds: seconds)
            sample.audio.packetsSent = sent
            sample.screen.sent.packetsSent = screenSent
            sample.packetsLostAtPartner = lost
            sample.roundTripSeconds = roundTrip
            if let available {
                videoBytes += 10_000
                sample.camera.sent.bytesSent = videoBytes
                sample.camera.qualityLimitation = "bandwidth"
                sample.availableOutgoingBitsPerSecond = available
            }
            if let screenAvailable {
                sample.screen.sent.bytesSent = screenSent * 1_000
                sample.screen.qualityLimitation = "bandwidth"
                sample.availableOutgoingBitsPerSecond = screenAvailable
            }
            return health.add(sample)
        }
    }

    @Test func aTwoSecondBlipNeverShows() {
        var feed = Feed()
        for _ in 0..<5 { feed.add() }
        feed.add(lossShare: 0.5)
        for _ in 0..<5 { feed.add() }
        feed.add(lossShare: 0.3)
        for _ in 0..<5 { feed.add() }
        #expect(!feed.health.isMineWeak)
    }

    @Test func steadyLossTurnsWeakAfterThreeBadSamples() {
        var feed = Feed()
        for _ in 0..<3 { feed.add() }
        feed.add(lossShare: 0.3)
        feed.add(lossShare: 0.3)
        #expect(!feed.health.isMineWeak)
        let turnedWeak = feed.add(lossShare: 0.3)
        #expect(turnedWeak)
        #expect(feed.health.isMineWeak)
    }

    @Test func weakStaysUntilFiveGoodSamplesInARow() {
        var feed = Feed()
        for _ in 0..<6 { feed.add(lossShare: 0.2) }
        #expect(feed.health.isMineWeak)
        // The 4-second loss window still holds the bad packets for one sample.
        for _ in 0..<5 { feed.add() }
        #expect(feed.health.isMineWeak)
        // A loss between the two thresholds starts the count again, and stays in the window for
        // one more sample.
        feed.add(lossShare: 0.12)
        for _ in 0..<5 { feed.add() }
        #expect(feed.health.isMineWeak)
        let turnedGood = feed.add()
        #expect(turnedGood)
        #expect(!feed.health.isMineWeak)
    }

    @Test func aSlowRoundTripIsWeakWithoutLoss() {
        var feed = Feed()
        for _ in 0..<4 { feed.add(roundTrip: 0.6) }
        #expect(feed.health.isMineWeak)
    }

    @Test func lossAmongAFewSilentPacketsIsIgnored() {
        var feed = Feed()
        for _ in 0..<6 { feed.add(lossShare: 0.5, packets: 10) }
        #expect(!feed.health.isMineWeak)
    }

    @Test func videoSqueezedByTheNetworkIsWeakOnlyWhenNextToNothingIsLeft() {
        var roomy = Feed()
        for _ in 0..<6 { roomy.add(videoLimitedTo: 400_000) }
        #expect(!roomy.health.isMineWeak)

        var squeezed = Feed()
        for _ in 0..<4 { squeezed.add(videoLimitedTo: 100_000) }
        #expect(squeezed.health.isMineWeak)
    }

    @Test func aSharedScreensLossesCountAgainstItsOwnPackets() {
        var feed = Feed(screenPackets: 400)
        for _ in 0..<6 { feed.add(lossShare: 0.06) }
        #expect(!feed.health.isMineWeak)
    }

    @Test func aSqueezedScreenIsWeakWhileItSendsWithoutTheCamera() {
        var feed = Feed(screenPackets: 100)
        for _ in 0..<4 { feed.add(screenLimitedTo: 100_000) }
        #expect(feed.health.isMineWeak)
    }

    @Test func eachPhoneNamesItsOwnEndWhenBothAreWeak() {
        var feed = Feed()
        #expect(feed.health.weakSide == nil)
        feed.health.isPartnersWeak = true
        #expect(feed.health.weakSide == .partners)
        for _ in 0..<4 { feed.add(lossShare: 0.3) }
        #expect(feed.health.weakSide == .mine)
    }
}

struct CallFrameGapsTests {
    private func gaps(framesEvery interval: TimeInterval, count: Int) -> (CallFrameGaps, TimeInterval) {
        var gaps = CallFrameGaps()
        var time = 100.0
        for _ in 0..<count {
            gaps.frameArrived(at: time)
            time += interval
        }
        return (gaps, time - interval)
    }

    @Test func nothingIsStalledBeforeTheFirstFrame() {
        #expect(!CallFrameGaps().isStalled(at: 1_000))
    }

    @Test func smoothVideoStallsAfterASecond() {
        let (gaps, last) = gaps(framesEvery: 1.0 / 30, count: 60)
        #expect(!gaps.isStalled(at: last + 0.99))
        #expect(gaps.isStalled(at: last + 1.01))
    }

    @Test func slowVideoWaitsLongerBeforeItCountsAsStalled() {
        let (gaps, last) = gaps(framesEvery: 0.5, count: 30)
        #expect(!gaps.isStalled(at: last + 1.49))
        #expect(gaps.isStalled(at: last + 1.51))
    }

    @Test func aStallNeverWaitsMoreThanThreeSeconds() {
        let (gaps, last) = gaps(framesEvery: 2, count: 30)
        #expect(!gaps.isStalled(at: last + 2.99))
        #expect(gaps.isStalled(at: last + 3.01))
    }
}

struct CallPowerStateTests {
    private func state(
        _ thermal: ProcessInfo.ThermalState = .nominal,
        lowPower: Bool = false,
        battery: Float? = 0.8,
        pluggedIn: Bool = false
    ) -> CallPowerState {
        CallPowerState(thermalState: thermal, isLowPowerMode: lowPower, batteryLevel: battery, isPluggedIn: pluggedIn)
    }

    @Test func heatFollowsTheThermalStateAndLowPowerMode() {
        #expect(state(.fair).heat == .normal)
        #expect(state(.fair, lowPower: true).heat == .warm)
        #expect(state(.serious).heat == .warm)
        #expect(state(.critical, lowPower: true).heat == .hot)
    }

    @Test func aHotPhoneOffersTheCameraOffFirst() {
        let hotAndLow = state(.critical, battery: 0.1)
        #expect(hotAndLow.cameraOffSuggestion(isCameraOn: true, dismissed: []) == .hot)
        #expect(hotAndLow.cameraOffSuggestion(isCameraOn: true, dismissed: [.hot]) == .lowBattery)
        #expect(hotAndLow.cameraOffSuggestion(isCameraOn: true, dismissed: [.hot, .lowBattery]) == nil)
        #expect(hotAndLow.cameraOffSuggestion(isCameraOn: false, dismissed: []) == nil)
        #expect(state(.serious).cameraOffSuggestion(isCameraOn: true, dismissed: []) == nil)
    }

    @Test func aLowBatteryCountsOnlyUnplugged() {
        #expect(state(battery: 0.2).cameraOffSuggestion(isCameraOn: true, dismissed: []) == .lowBattery)
        #expect(state(battery: 0.25).cameraOffSuggestion(isCameraOn: true, dismissed: []) == nil)
        #expect(state(battery: 0.1, pluggedIn: true).cameraOffSuggestion(isCameraOn: true, dismissed: []) == nil)
        #expect(state(battery: nil).cameraOffSuggestion(isCameraOn: true, dismissed: []) == nil)
    }
}

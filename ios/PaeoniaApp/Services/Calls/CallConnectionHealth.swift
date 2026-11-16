import Foundation

/// Whose end of the call is weak. Each phone judges from its stats samples whether what it sends
/// reaches the partner badly, and tells the other over the relay (`CallSignal.Message.connection`).
///
/// A sample is bad when, over the last 4 seconds, the partner's phone missed 10% or more of the
/// packets, the round trip took half a second or more, or the video had under 150 kbps to use.
/// It is good when the loss is under 4%, the round trip under 0.3 seconds and the video has
/// 250 kbps or more. Anything between is neither. The connection turns weak after 3 bad samples
/// in a row, about 6 seconds, so a blip of a second or two never shows, and turns fine again only
/// after 5 good samples in a row, about 10 seconds, so the warning does not flicker. The video is
/// the camera's, or the shared screen's while it sends without the camera.
nonisolated struct CallConnectionHealth {
    static let enterStreak = 3
    static let exitStreak = 5
    /// How many samples back the loss is measured, 4 seconds at one sample every 2 seconds.
    /// A receiver report for audio comes only every few seconds, so a shorter window swings.
    static let lossWindow = 2
    /// Below this many packets the loss says nothing, such as while both people are silent and
    /// the audio sends almost nothing (Opus DTX).
    static let minPacketsForLoss = 40

    /// What this phone sends reaches the partner badly.
    private(set) var isMineWeak = false
    /// The partner's phone said what it sends reaches this phone badly.
    var isPartnersWeak = false
    private var recent: [CallStatsSample] = []
    private var badStreak = 0
    private var goodStreak = 0

    /// Adds this phone's newest sample. Returns true when `isMineWeak` changed.
    mutating func add(_ sample: CallStatsSample) -> Bool {
        recent.append(sample)
        if recent.count > Self.lossWindow + 1 {
            recent.removeFirst()
        }
        guard recent.count > 1 else { return false }
        switch grade(sample, since: recent[0], previous: recent[recent.count - 2]) {
        case .bad:
            badStreak += 1
            goodStreak = 0
        case .good:
            goodStreak += 1
            badStreak = 0
        case .unclear:
            badStreak = 0
            goodStreak = 0
        }
        let wasWeak = isMineWeak
        if !isMineWeak, badStreak >= Self.enterStreak {
            isMineWeak = true
        } else if isMineWeak, goodStreak >= Self.exitStreak {
            isMineWeak = false
        }
        return isMineWeak != wasWeak
    }

    /// Whose end to name. When both phones send badly, one person's network is usually weak both
    /// ways, and neither phone can tell whose, so each tells its own person to check theirs.
    var weakSide: CallWeakSide? {
        if isMineWeak { return .mine }
        return isPartnersWeak ? .partners : nil
    }

    private enum Grade {
        case bad
        case good
        case unclear
    }

    private func grade(_ sample: CallStatsSample, since earliest: CallStatsSample, previous: CallStatsSample) -> Grade {
        // The partner's receiver reports count the shared screen's losses too.
        let sent = Self.packetsSent(sample) - Self.packetsSent(earliest)
        let lost = max(sample.packetsLostAtPartner - earliest.packetsLostAtPartner, 0)
        let loss = sent >= Self.minPacketsForLoss ? Double(lost) / Double(sent) : nil
        let roundTrip = sample.roundTripSeconds
        // WebRTC lowers the video for the network estimate on most calls. It means a weak
        // connection only when the estimate leaves the video next to nothing.
        let videoRoom = Self.isVideoShortOfBits(sample, previous: previous)
            ? sample.availableOutgoingBitsPerSecond
            : nil

        if (loss ?? 0) >= 0.10 || (roundTrip ?? 0) >= 0.5 || (videoRoom ?? .infinity) < 150_000 {
            return .bad
        }
        if (loss ?? 0) < 0.04, (roundTrip ?? 0) < 0.3, (videoRoom ?? .infinity) >= 250_000 {
            return .good
        }
        return .unclear
    }

    private static func packetsSent(_ sample: CallStatsSample) -> Int {
        sample.audio.packetsSent + sample.video.packetsSent + sample.screen.sent.packetsSent
    }

    private static func isVideoShortOfBits(_ sample: CallStatsSample, previous: CallStatsSample) -> Bool {
        if sample.video.bytesSent > previous.video.bytesSent {
            return sample.qualityLimitation == "bandwidth"
        }
        return sample.screen.sent.bytesSent > previous.screen.sent.bytesSent
            && sample.screen.qualityLimitation == "bandwidth"
    }
}

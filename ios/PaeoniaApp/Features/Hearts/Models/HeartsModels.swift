import Foundation

/// The result of `hearts:get_hearts`: what the partner has sent this person, and how
/// much of it this person has already been shown.
nonisolated struct RemoteHeartsState: Decodable, Equatable, Sendable {
    let coupleID: UUID
    let receivedTotal: Int
    let receivedSeenTotal: Int

    enum CodingKeys: String, CodingKey {
        case coupleID = "couple_id"
        case receivedTotal = "received_total"
        case receivedSeenTotal = "received_seen_total"
    }
}

/// `hearts:send_hearts`. The count is one batch of taps.
nonisolated struct HeartsSendPayload: Codable, Equatable, Sendable {
    let count: Int
}

/// `hearts:mark_hearts_seen`. The total of the partner's hearts this person was shown.
nonisolated struct HeartsSeenPayload: Codable, Equatable, Sendable {
    let seenTotal: Int
}

/// The partner's hearts as this phone knows them. Unseen hearts are the difference
/// between what the partner sent and what this phone has shown, so a heart that
/// arrives while others play stays unseen until the next burst.
nonisolated struct HeartsInbox: Codable, Equatable, Sendable {
    var coupleID: UUID?
    var receivedTotal = 0
    /// The most the server or this phone says was shown.
    var seenTotal = 0

    var unseenCount: Int {
        max(0, receivedTotal - seenTotal)
    }

    /// Takes the server's answer. The totals only grow, so an older answer that
    /// arrives late changes nothing. A different couple, or totals that went down
    /// (the server's data was restored), start over from the server's numbers.
    mutating func apply(_ server: RemoteHeartsState) {
        let startsOver = coupleID != server.coupleID || server.receivedTotal < receivedTotal
        coupleID = server.coupleID
        if startsOver {
            receivedTotal = server.receivedTotal
            seenTotal = server.receivedSeenTotal
        } else {
            receivedTotal = max(receivedTotal, server.receivedTotal)
            seenTotal = max(seenTotal, server.receivedSeenTotal)
        }
        seenTotal = min(seenTotal, receivedTotal)
    }

    /// The hearts a burst would show now, or nil when nothing is unseen.
    var pendingBurst: HeartsShown? {
        unseenCount > 0 ? HeartsShown(count: unseenCount, total: receivedTotal) : nil
    }

    /// This phone showed the partner's hearts up to `total`. Hearts that arrived
    /// after `total` stay unseen, and the total never goes down.
    mutating func markShown(upTo total: Int) {
        seenTotal = max(seenTotal, min(total, receivedTotal))
    }
}

/// The hearts one burst shows.
nonisolated struct HeartsShown: Equatable, Sendable {
    /// Hearts the person was not shown before.
    let count: Int
    /// The partner's total after this burst, which the server marks as seen.
    let total: Int
}

/// One burst of the partner's hearts to play.
nonisolated struct HeartsBurst: Identifiable, Equatable, Sendable {
    let id = UUID()
    /// Every heart in the burst, for the line that says how many came.
    let count: Int

    /// Hearts that fly. A big burst stays readable and cheap to draw.
    static let maxFlying = 12

    var flyingCount: Int {
        min(count, Self.maxFlying)
    }
}

/// Groups taps into sends. A send waits until the taps stop for `quietPeriod`, and
/// carries at most `maxPerSend` hearts, which is what the server accepts per call.
nonisolated struct HeartsTapBatcher: Equatable, Sendable {
    static let quietPeriod: Duration = .milliseconds(1_500)
    static let maxPerSend = 100

    private(set) var pendingTaps = 0

    var hasPendingTaps: Bool {
        pendingTaps > 0
    }

    mutating func tap() {
        pendingTaps += 1
    }

    /// The counts to send now, each at most `maxPerSend`, and forgets them.
    mutating func takeBatches() -> [Int] {
        var remaining = pendingTaps
        pendingTaps = 0
        var batches: [Int] = []
        while remaining > 0 {
            let batch = min(remaining, Self.maxPerSend)
            batches.append(batch)
            remaining -= batch
        }
        return batches
    }
}

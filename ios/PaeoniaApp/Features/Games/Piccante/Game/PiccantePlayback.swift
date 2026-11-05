import Foundation

/// Maps server deadlines onto this phone's clock using a request's midpoint.
nonisolated struct PiccantePlaybackClock: Sendable {
    let offset: TimeInterval

    init(serverTime: Date, sentAt: Date, receivedAt: Date) {
        offset = serverTime.timeIntervalSince(sentAt.addingTimeInterval(receivedAt.timeIntervalSince(sentAt) / 2))
    }

    func localDate(for serverTime: Date) -> Date {
        serverTime.addingTimeInterval(-offset)
    }
}

nonisolated struct PiccanteBitePlayback: Sendable {
    let startsAt: Date
    let playsSound: Bool
}

nonisolated enum PiccantePlayback {
    static func plan(bite: PiccanteBite, clock: PiccantePlaybackClock?, reduceMotion: Bool, now: Date)
        -> PiccanteBitePlayback
    {
        let deadline = clock?.localDate(for: bite.playAt)
        let historical = (deadline ?? bite.playAt).timeIntervalSince(now) < -2
        let replaysLocally = deadline == nil || historical
        return PiccanteBitePlayback(
            startsAt: replaysLocally ? now.addingTimeInterval(reduceMotion && historical ? 0 : 0.32) : deadline ?? now,
            playsSound: !reduceMotion || !historical)
    }

    /// The bite's ordinal is shared, so both phones choose the same recording.
    static func variation(gameNumber: Int, biteIndex: Int) -> Int {
        (gameNumber % 5 + biteIndex % 5) % 5
    }

    static func delay(until deadline: Date, now: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }
}

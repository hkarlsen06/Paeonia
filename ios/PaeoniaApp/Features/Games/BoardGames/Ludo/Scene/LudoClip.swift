import Foundation

/// One animation of one thing in the scene. The stage plays clips each frame:
/// it hands a clip the seconds since it began, clamped to its length, so a clip
/// that has not begun shows its first pose and a clip that is over shows its last.
@MainActor
final class LudoClip {
    enum Owner: Hashable {
        case pawn(Int)
        case die
        case glow(Int)
    }

    /// Something that happens at a time in the clip, such as a tap on the phone.
    struct Event {
        let time: Double
        let action: () -> Void
    }

    let owner: Owner
    /// When the clip begins, on the stage clock.
    let start: Double
    let duration: Double
    /// True for the die's tumble, which later die states wait for.
    let isTumble: Bool
    private let pose: (Double) -> Void
    private var events: [Event]
    var onFinish: (() -> Void)?

    init(
        owner: Owner,
        start: Double,
        duration: Double,
        isTumble: Bool = false,
        events: [Event] = [],
        pose: @escaping (Double) -> Void
    ) {
        self.owner = owner
        self.start = start
        self.duration = duration
        self.isTumble = isTumble
        self.events = events.sorted { $0.time < $1.time }
        self.pose = pose
    }

    var end: Double { start + duration }

    /// Plays the clip up to the stage clock `now`. Returns true when it is over.
    func play(at now: Double) -> Bool {
        let local = now - start
        pose(min(max(local, 0), duration))
        while let next = events.first, local >= next.time {
            events.removeFirst()
            next.action()
        }
        return local >= duration
    }

    /// Jumps to the last pose without the events.
    func finishNow() {
        pose(duration)
        events.removeAll()
    }
}

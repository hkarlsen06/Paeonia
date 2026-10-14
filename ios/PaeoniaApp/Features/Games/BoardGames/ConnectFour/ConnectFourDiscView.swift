import SwiftUI

/// One disc in its owner's color, with a soft highlight, the ridge a real disc
/// has, and the owner's mark in the middle.
struct ConnectFourDiscView: View {
    let style: BoardPieceStyle
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(style.color)
            Circle().fill(
                RadialGradient(
                    colors: [Color.paeoniaTextPrimary.opacity(0.3), .clear],
                    center: UnitPoint(x: 0.34, y: 0.28),
                    startRadius: 0,
                    endRadius: diameter * 0.7
                )
            )
            Circle().fill(
                LinearGradient(
                    colors: [.clear, Color.paeoniaBackgroundSecondary.opacity(0.22)],
                    startPoint: UnitPoint(x: 0.5, y: 0.5),
                    endPoint: .bottom
                )
            )
            Circle()
                .strokeBorder(Color.paeoniaBackgroundSecondary.opacity(0.2), lineWidth: max(1, diameter * 0.025))
                .padding(diameter * 0.14)
            // Dark on the solid disc. A light mark reads at only about 2.3:1 on
            // either piece color, and the mark is what tells the players apart for
            // someone who can't tell the colors apart.
            BoardMarkView(style: style, tint: .paeoniaTextInverse)
                .frame(width: diameter * 0.55, height: diameter * 0.55)
                .shadow(color: Color.paeoniaTextPrimary.opacity(0.35), radius: 0.8, y: 0.8)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// A disc on its way to its cell. `id` is the number of the move that dropped it.
nonisolated struct ConnectFourFallingDisc: Identifiable, Equatable {
    let id: Int
    /// The cell the disc lands in.
    let index: Int
    let player: BoardPlayer
    let isMine: Bool
    let start: Date
    let motion: ConnectFourDropMotion

    init(move: BoardMoveEvent, index: Int, start: Date, motion: ConnectFourDropMotion) {
        id = move.number
        self.index = index
        player = move.player
        isMine = move.isMine
        self.start = start
        self.motion = motion
    }

    /// When the disc has stopped moving.
    var end: Date { start.addingTimeInterval(motion.totalDuration) }
}

/// Draws a falling disc every frame and taps once when it lands. It sits behind
/// the board face, so the face hides it as it passes. It tells its parent when it
/// has settled, and the parent then draws the disc in its cell instead.
struct ConnectFourFallingDiscView: View {
    let disc: ConnectFourFallingDisc
    let style: BoardPieceStyle
    let geometry: ConnectFourBoardGeometry
    let onFinished: (Int) -> Void

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(disc.start)
            let rest = geometry.cellCenter(index: disc.index)
            let lift = CGFloat(disc.motion.height(at: elapsed)) * geometry.cell
            ConnectFourDiscView(style: style, diameter: geometry.discDiameter)
                .opacity(disc.motion.opacity(at: elapsed))
                .position(x: rest.x, y: rest.y - lift)
        }
        .task { await land() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func land() async {
        await ConnectFourClock.sleep(until: disc.start.addingTimeInterval(disc.motion.landingTime))
        guard !Task.isCancelled else { return }
        if disc.isMine {
            PaeoniaHaptics.drawingSent()
        } else {
            PaeoniaHaptics.streakTick(intensity: 0.6)
        }
        await ConnectFourClock.sleep(until: disc.end)
        guard !Task.isCancelled else { return }
        onFinished(disc.id)
    }
}

import SwiftUI

/// The line on the reveal, at a larger size: this person's pin standing, the
/// partner's pin dropping in, the gold thread between them, and a soft glow
/// behind that peaks on a spot on. Two pins that land close lean apart at the
/// verdict until their heads touch, so both stay readable.
struct ConsensioRevealStage: View {
    let round: RemoteConsensioRound?
    let myValue: Int?
    let partnerValue: Int?
    let myStyle: BoardPieceStyle
    let partnerStyle: BoardPieceStyle
    let timeline: ConsensioRevealTimeline
    let pulseScale: CGFloat
    let isWide: Bool
    let a11yValue: LocalizedStringResource
    /// The guess was far off, so the thread draws dashed from the start.
    let isFar: Bool
    let isSpotOn: Bool

    @State private var width: CGFloat = 340
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far above its spot the partner's pin starts its drop.
    private static let dropHeight: CGFloat = 90

    private var pinScale: CGFloat { isWide ? 2.4 : 1.7 }

    var body: some View {
        ZStack {
            glow
            ConsensioScale(
                subject: round?.subject ?? "",
                leftEnd: round?.leftEnd ?? "",
                rightEnd: round?.rightEnd ?? "",
                pins: pins,
                thread: thread,
                isDimmed: timeline.dimmed,
                pinScale: pinScale
            )
            .accessibilityValue(Text(a11yValue))
        }
        .frame(maxWidth: isWide ? 640 : .infinity)
        .padding(.vertical, PaeoniaSpacing.space16)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    // MARK: Glow

    private var glowStrength: Double {
        switch timeline.verdict {
        case .spotOn: 0.55
        case .soClose, .close: 0.3
        case .far: 0.1
        case nil: timeline.dimmed ? 0.16 : 0
        }
    }

    /// A blurred ellipse, so the light has no edge.
    private var glow: some View {
        let middle = CGFloat((myValue ?? 50) + (partnerValue ?? myValue ?? 50)) / 200
        return Ellipse()
            .fill(Color.paeoniaAccentPrimary.opacity(glowStrength))
            .frame(width: max(240, width * 0.8), height: 260)
            .blur(radius: 70)
            .offset(x: (middle - 0.5) * width, y: -10)
            .animation(PaeoniaMotion.standardCurve(duration: PaeoniaMotion.motionSlow), value: glowStrength)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Pins

    /// The lean that makes two close heads touch instead of overlap, in degrees,
    /// for the pin on the left. The one on the right leans the same the other way.
    private var splay: Double {
        // The partner's pin lands already leaning, so the two never overlap.
        guard timeline.dropped, let mine = myValue, let theirs = partnerValue else { return 0 }
        let head = ConsensioMarker.headSize * pinScale
        let unit = max(1, width - head) / CGFloat(ConsensioRules.maxSpot)
        let gap = CGFloat(abs(mine - theirs)) * unit
        guard gap < head else { return 0 }
        // The head's center stands this far above the foot of the stem.
        let reach = (ConsensioMarker.height - ConsensioMarker.headSize / 2) * pinScale
        let push = (head - gap) / 2
        return Double(asin(min(0.6, push / reach))) * 180 / .pi
    }

    private var pins: [ConsensioScale.Pin] {
        guard let mine = myValue else { return [] }
        let glow: CGFloat = switch timeline.verdict {
        case .spotOn: 1
        case .soClose, .close: 0.5
        default: 0
        }
        let mineIsLeft = (partnerValue ?? mine) >= mine
        var pins: [ConsensioScale.Pin] = []
        if let theirs = partnerValue {
            pins.append(ConsensioScale.Pin(
                id: "partner",
                position: theirs,
                style: partnerStyle,
                glow: glow,
                lift: timeline.dropped ? 0 : Self.dropHeight,
                opacity: timeline.dropped ? 1 : 0,
                tilt: mineIsLeft ? splay : -splay
            ))
        }
        pins.append(ConsensioScale.Pin(
            id: "mine",
            position: mine,
            style: myStyle,
            pulseScale: pulseScale,
            glow: glow,
            tilt: mineIsLeft ? -splay : splay
        ))
        return pins
    }

    private var thread: ConsensioScale.Thread? {
        // A spot on needs no thread: the heads touch and the bloom says it.
        guard let mine = myValue, let theirs = partnerValue, !isSpotOn, mine != theirs, timeline.thread > 0 else {
            return nil
        }
        return ConsensioScale.Thread(
            from: mine,
            to: theirs,
            progress: timeline.thread,
            isDashed: isFar
        )
    }
}

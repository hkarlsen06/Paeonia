import SwiftUI

/// The line every phase shares: a straight track between two ends, with pins
/// standing on it. One pin can be the person's own, moved by touch. The real spot
/// is never drawn before the reveal, so nothing here hints at it.
struct ConsensioScale: View {
    /// A pin that only shows.
    struct Pin: Identifiable {
        let id: String
        let position: Int
        let style: BoardPieceStyle
        var isLifted = false
        var pulseScale: CGFloat = 1
        var glow: CGFloat = 0
        /// Points above its place on the line, for the drop on the reveal.
        var lift: CGFloat = 0
        var opacity: Double = 1
        /// Degrees the pin leans (see `ConsensioMarker.tilt`).
        var tilt: Double = 0
    }

    /// The pin the person moves, with what happens when they move it.
    struct Editable {
        let position: Int?
        let style: BoardPieceStyle
        /// The finger moved the pin to a position, or let go of it.
        let move: (_ position: Int, _ isTouching: Bool) -> Void
    }

    /// The gold thread between two spots on the reveal.
    struct Thread {
        let from: Int
        let to: Int
        /// How much is drawn, 0 to 1, from `from` toward `to`.
        let progress: Double
        var isDashed = false
    }

    let subject: String
    let leftEnd: String
    let rightEnd: String
    var pins: [Pin] = []
    var editable: Editable?
    var thread: Thread?
    /// The track and the ends fade back while the reveal builds up. The pins stay bright.
    var isDimmed = false
    /// Shown over the track while the editable pin is not placed.
    var hint: LocalizedStringResource?
    /// The track between `warmth.from` and `warmth.to` glows gold, for the placer's
    /// "close" while the partner guesses live.
    var warmth: (from: Int, to: Int)?
    /// The pins' size: 1 where a pin is moved, larger on the reveal.
    var pinScale: CGFloat = 1

    @State private var isTouching = false
    @State private var lastTickBucket: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let trackHeight: CGFloat = 4
    /// Room above the track for a lifted pin.
    private var pinArea: CGFloat { ConsensioMarker.height * pinScale + 10 }
    private var inset: CGFloat { ConsensioMarker.headSize * pinScale / 2 }
    private static let tickStep = 5

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            lineArea
            ends
        }
        .accessibilityElement(children: .ignore)
        .modifier(ScaleAccessibility(
            subject: subject,
            leftEnd: leftEnd,
            rightEnd: rightEnd,
            editable: editable,
            readOnlyPins: pins
        ))
    }

    // MARK: Line

    /// Everything on the line is placed at absolute points in one fixed frame, so a
    /// hint, a pin or the thread can never push another part out of place.
    private var lineArea: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                trackLayer(width: width)
                pinLayer(width: width)
            }
            .frame(width: width, height: areaHeight)
            .contentShape(Rectangle())
            .gesture(editable.map { dragGesture($0, width: width) })
        }
        .frame(height: areaHeight)
    }

    /// The track, its glow and dots, the thread, and the hint.
    @ViewBuilder
    private func trackLayer(width: CGFloat) -> some View {
        Capsule()
            .fill(.paeoniaSurfacePrimary)
            .frame(width: width, height: Self.trackHeight)
            .opacity(isDimmed ? 0.3 : 1)
            .position(x: width / 2, y: trackY)
        if let warmth {
            let start = x(for: min(warmth.from, warmth.to), width: width)
            let end = x(for: max(warmth.from, warmth.to), width: width)
            Capsule()
                .fill(Color.paeoniaInkGold.opacity(0.35))
                .frame(width: max(Self.trackHeight + 4, end - start), height: Self.trackHeight + 4)
                .position(x: (start + end) / 2, y: trackY)
                .transition(.opacity)
        }
        ForEach([25, 50, 75], id: \.self) { mark in
            Circle()
                .fill(.paeoniaTextTertiary)
                .frame(width: 5, height: 5)
                .position(x: x(for: mark, width: width), y: trackY)
        }
        if let thread {
            threadView(thread, width: width)
        }
        if let hint, let editable, editable.position == nil {
            Text(hint)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .position(x: width / 2, y: trackY - PaeoniaSpacing.space32)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func pinLayer(width: CGFloat) -> some View {
        ForEach(pins) { pin in
            ConsensioMarker(
                style: pin.style,
                isLifted: pin.isLifted,
                pulseScale: pin.pulseScale,
                glow: pin.glow,
                size: pinScale,
                tilt: pin.tilt
            )
            .opacity(pin.opacity)
            .position(x: x(for: pin.position, width: width), y: pinCenterY - pin.lift)
        }
        if let editable {
            editablePin(editable, width: width)
        }
    }

    private var trackY: CGFloat { pinArea + Self.trackHeight / 2 }
    private var areaHeight: CGFloat { pinArea + Self.trackHeight + PaeoniaSpacing.space8 }

    /// A pin's stem ends on the track.
    private var pinCenterY: CGFloat {
        trackY - ConsensioMarker.height * pinScale / 2
    }

    private func editablePin(_ editable: Editable, width: CGFloat) -> some View {
        Group {
            if let position = editable.position {
                ConsensioMarker(style: editable.style, isLifted: isTouching)
                    .position(x: x(for: position, width: width), y: pinCenterY)
                    .animation(reduceMotion ? nil : PaeoniaMotion.cardReveal, value: isTouching)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.6, anchor: .bottom)))
            }
        }
    }

    /// A gold arc from one head to the other, drawn from `from`. Pins whose heads
    /// touch need no thread.
    /// A gold arc from one head to the other, drawn from `from`. When the heads
    /// touch, a short gold segment on the track joins the two stems instead.
    @ViewBuilder
    private func threadView(_ thread: Thread, width: CGFloat) -> some View {
        let start = x(for: thread.from, width: width)
        let end = x(for: thread.to, width: width)
        let head = ConsensioMarker.headSize * pinScale
        let color = thread.isDashed ? Color.paeoniaTextSecondary : Color.paeoniaInkGold
        let style = StrokeStyle(lineWidth: 4, lineCap: .round, dash: thread.isDashed ? [6, 7] : [])
        if abs(end - start) > head {
            let headY = trackY - ConsensioMarker.height * pinScale + head / 2
            let inward = (end > start ? 1 : -1) * head / 2
            let from = CGPoint(x: start + inward, y: headY)
            let to = CGPoint(x: end - inward, y: headY)
            let lift = min(48, abs(to.x - from.x) * 0.35)
            Path { path in
                path.move(to: from)
                path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: headY - lift))
            }
            .trim(from: 0, to: thread.progress)
            .stroke(color, style: style)
            .shadow(color: thread.isDashed ? .clear : Color.paeoniaInkGold.opacity(0.8), radius: 6)
        } else {
            Path { path in
                path.move(to: CGPoint(x: start, y: trackY))
                path.addLine(to: CGPoint(x: end, y: trackY))
            }
            .trim(from: 0, to: thread.progress)
            .stroke(color, style: style)
            .shadow(color: Color.paeoniaInkGold.opacity(0.8), radius: 5)
        }
    }

    // MARK: Ends

    private var ends: some View {
        HStack(alignment: .top, spacing: PaeoniaSpacing.space16) {
            Text(leftEnd)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(rightEnd)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .font(PaeoniaTypography.bodyEmphasis)
        .foregroundStyle(.paeoniaTextSecondary)
        .opacity(isDimmed ? 0.4 : 1)
        .lineLimit(3)
    }

    // MARK: Geometry

    private func x(for position: Int, width: CGFloat) -> CGFloat {
        inset + (width - 2 * inset) * CGFloat(position) / CGFloat(ConsensioRules.maxSpot)
    }

    private func position(for x: CGFloat, width: CGFloat) -> Int {
        let usable = max(1, width - 2 * inset)
        let value = ((x - inset) / usable * CGFloat(ConsensioRules.maxSpot)).rounded()
        return Int(min(max(value, 0), CGFloat(ConsensioRules.maxSpot)))
    }

    private func dragGesture(_ editable: Editable, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let position = position(for: value.location.x, width: width)
                if !isTouching {
                    isTouching = true
                    PaeoniaHaptics.selection()
                    GameSound.tap.play(volume: 0.5)
                }
                tickIfNeeded(position)
                editable.move(position, true)
            }
            .onEnded { value in
                isTouching = false
                lastTickBucket = nil
                editable.move(position(for: value.location.x, width: width), false)
            }
    }

    /// A light tick every 5 positions the pin moves.
    private func tickIfNeeded(_ position: Int) {
        let bucket = position / Self.tickStep
        defer { lastTickBucket = bucket }
        guard let lastTickBucket, lastTickBucket != bucket else { return }
        PaeoniaHaptics.selection()
        GameSound.tick.play(volume: 0.4)
    }
}

// MARK: - VoiceOver

/// The line is one adjustable element. A swipe moves the pin by 5, the custom
/// actions by 1. Before the pin is placed, "Place your marker" puts it in the
/// middle. A read-only line reads where each pin is.
private struct ScaleAccessibility: ViewModifier {
    let subject: String
    let leftEnd: String
    let rightEnd: String
    let editable: ConsensioScale.Editable?
    let readOnlyPins: [ConsensioScale.Pin]

    func body(content: Content) -> some View {
        if let editable {
            content
                .accessibilityLabel(Text(verbatim: subject))
                .accessibilityValue(Text(Self.value(editable.position, leftEnd: leftEnd, rightEnd: rightEnd)))
                .accessibilityHint(Text(.consensioScaleHint(Self.inSentence(leftEnd), Self.inSentence(rightEnd))))
                .accessibilityAdjustableAction { direction in
                    let current = editable.position ?? 50
                    switch direction {
                    case .increment: editable.move(min(current + 5, ConsensioRules.maxSpot), false)
                    case .decrement: editable.move(max(current - 5, 0), false)
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: Text(.consensioScalePlace)) {
                    if editable.position == nil { editable.move(50, false) }
                }
                .accessibilityAction(named: Text(.consensioScaleLeft)) {
                    editable.move(max((editable.position ?? 50) - 1, 0), false)
                }
                .accessibilityAction(named: Text(.consensioScaleRight)) {
                    editable.move(min((editable.position ?? 50) + 1, ConsensioRules.maxSpot), false)
                }
                .accessibilityIdentifier("consensio.scale")
        } else {
            content
                .accessibilityLabel(Text(verbatim: subject))
                .accessibilityHint(Text(.consensioScaleRange(Self.inSentence(leftEnd), Self.inSentence(rightEnd))))
                .accessibilityIdentifier("consensio.scale")
        }
    }

    static func value(_ position: Int?, leftEnd: String, rightEnd: String) -> LocalizedStringResource {
        ConsensioScaleValue.text(position, leftEnd: leftEnd, rightEnd: rightEnd)
    }

    static func inSentence(_ end: String) -> String {
        ConsensioEndText.inSentence(end)
    }
}

/// Where a pin is, in words: "62 percent of the way to book it now", "In the
/// middle", or "Not placed yet". VoiceOver reads it, and the reveal's announcement.
nonisolated enum ConsensioScaleValue {
    static func text(_ position: Int?, leftEnd: String, rightEnd: String) -> LocalizedStringResource {
        guard let position else { return .consensioScaleEmpty }
        if ConsensioRules.middleRange.contains(position) { return .consensioScaleMiddle }
        return position > 50
            ? .consensioScaleValue(position, ConsensioEndText.inSentence(rightEnd))
            : .consensioScaleValue(ConsensioRules.maxSpot - position, ConsensioEndText.inSentence(leftEnd))
    }

    /// Where a spot of `round` is, in words.
    static func string(_ position: Int?, in round: RemoteConsensioRound) -> String {
        String(localized: text(position, leftEnd: round.leftEnd, rightEnd: round.rightEnd))
    }
}

/// How an end reads in the middle of a sentence.
nonisolated enum ConsensioEndText {
    /// The first letter lowercased, unless the end starts with two capitals (an
    /// acronym) or the app is in Norwegian, where the copy puts the end in quotes.
    static func inSentence(_ end: String) -> String {
        guard Bundle.main.preferredLocalizations.first != "nb",
              let first = end.first, first.isUppercase else { return end }
        let second = end.dropFirst().first
        if let second, second.isUppercase { return end }
        return first.lowercased() + end.dropFirst()
    }
}

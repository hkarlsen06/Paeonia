import SwiftUI

/// The story as one flowing paragraph.
///
/// - Drawing. A custom `TextRenderer` draws the paragraph. The line in
///   `content.arrivingLineID` writes itself in word by word, and the partner's
///   draft ends the paragraph with a blinking caret.
/// - Taps. The renderer records where each line sits. A tap calls `onTapLine`
///   with the line and a rectangle around the tapped row, in this view's own
///   coordinate space, for a popover to point at.
/// - VoiceOver. The painted paragraph is hidden. Each line is its own element.
///
/// The view starts the write-in when `arrivingLineID` changes, and calls
/// `onArrivalFinished` when the line has landed. Until the write-in starts, the
/// arriving line stays hidden, so a new line never flashes onto the page.
struct StoryChainPageText: View {
    let content: StoryChainPageContent
    /// The VoiceOver name for my own lines, such as "You".
    let youLabel: String
    /// The VoiceOver name for Paeonia's opening, such as "Opening".
    let openingLabel: String
    var onTapLine: (UUID, CGRect) -> Void = { _, _ in }
    var onArrivalFinished: (UUID) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames = StoryChainLineFrames()
    @State private var arrivalStart: ArrivalStart?
    @State private var finishedLineID: UUID?

    private struct ArrivalStart: Equatable {
        let lineID: UUID
        let date: Date
    }

    /// While only the caret blinks, the page redraws this often. The write-in redraws on every frame.
    private static let caretFrameInterval: TimeInterval = 1.0 / 20

    var body: some View {
        let paragraph = StoryChainParagraph.text(for: content)
            .font(StoryChainPageStyle.bodyFont)
            .lineSpacing(StoryChainPageStyle.lineSpacing)
            .fixedSize(horizontal: false, vertical: true)
        let arriving = isArriving
        TimelineView(.animation(
            minimumInterval: arriving ? nil : Self.caretFrameInterval,
            paused: !arriving && content.ghost == nil
        )) { context in
            paragraph.textRenderer(renderer(at: context.date))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { location in
            if let hit = frames.hit(at: location) {
                onTapLine(hit.lineID, hit.rect)
            }
        }
        .accessibilityRepresentation {
            accessibleLines
        }
        .task(id: content.arrivingLineID) {
            await runArrival()
        }
    }

    // MARK: Drawing

    private var isArriving: Bool {
        guard let id = content.arrivingLineID else { return false }
        return finishedLineID != id
    }

    private func renderer(at date: Date) -> StoryChainPageRenderer {
        var timing = content.arrivalPace
        timing.fadeDuration = PaeoniaMotion.motionDefault
        return StoryChainPageRenderer(
            arrival: arrival(at: date),
            timing: timing,
            reduceMotion: reduceMotion,
            caretOpacity: StoryChainCaret.opacity(at: date),
            frames: frames
        )
    }

    /// The arriving line and how long it has been going. A line that has not
    /// started yet counts as 0 seconds in, which keeps it hidden.
    private func arrival(at date: Date) -> StoryChainPageRenderer.Arrival? {
        guard isArriving, let id = content.arrivingLineID else { return nil }
        guard let start = arrivalStart, start.lineID == id else {
            return StoryChainPageRenderer.Arrival(lineID: id, elapsed: 0)
        }
        return StoryChainPageRenderer.Arrival(lineID: id, elapsed: date.timeIntervalSince(start.date))
    }

    // MARK: Arrival

    private func runArrival() async {
        guard let id = content.arrivingLineID else {
            arrivalStart = nil
            finishedLineID = nil
            return
        }
        finishedLineID = nil
        arrivalStart = ArrivalStart(lineID: id, date: Date())
        let line = content.lines.first(where: { $0.id == id })
        let wordCount = line.map { StoryChainWords.count(in: $0.text) } ?? 0
        var timing = content.arrivalPace
        timing.fadeDuration = PaeoniaMotion.motionDefault
        let duration = timing.totalDuration(wordCount: wordCount, reduceMotion: reduceMotion)
        // A short extra wait lets the last frame draw before the line counts as done.
        try? await Task.sleep(for: .seconds(duration + 0.05))
        guard !Task.isCancelled else { return }
        finishedLineID = id
        onArrivalFinished(id)
    }

    // MARK: VoiceOver

    /// What VoiceOver says for one line: "Robin: text", or "You: text" for mine.
    static func spokenText(for line: StoryChainPageLine, youLabel: String) -> String {
        "\(line.isMine ? youLabel : line.authorName): \(line.text)"
    }

    static func spokenText(opening: String, openingLabel: String) -> String {
        "\(openingLabel): \(opening)"
    }

    private var accessibleLines: some View {
        VStack(alignment: .leading) {
            if let opening = content.opening, !opening.isEmpty {
                Text(verbatim: Self.spokenText(opening: opening, openingLabel: openingLabel))
            }
            ForEach(content.lines) { line in
                Text(verbatim: Self.spokenText(for: line, youLabel: youLabel))
            }
        }
    }
}

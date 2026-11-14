import SwiftUI

/// Games finished one after another, as one line. Opened, the games follow it as their own lines.
struct GameChatResultRunRow: View {
    let run: GameChatResultRun
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            GameChatResultLine(isExpanded: run.isExpanded, isFilled: true) {
                Text(.gamesConversationResultRunTitle(run.results.count))
            } time: {
                timeSpan
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            Text(run.isExpanded ? .gamesConversationResultExpanded : .gamesConversationResultCollapsed)
        )
        .accessibilityIdentifier("game.conversation.run.\(run.id.uuidString.lowercased())")
        .padding(.horizontal, PaeoniaSpacing.space12)
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        .frame(maxWidth: .infinity)
    }

    /// The day divider above already names the day, so the span shows only the times.
    private var timeSpan: Text {
        let first = run.results[0].reference.finishedAt
        let last = run.results[run.results.count - 1].reference.finishedAt
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .minute) {
            return Text(first, format: .dateTime.hour().minute())
        }
        return Text(first..<last, format: .interval.hour().minute())
    }
}

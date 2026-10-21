#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit

struct DailyQuestionLockScreenView: View {
    let entry: LockScreenEntry

    private var state: LockScreenQuestionState? {
        entry.snapshot.flatMap { LockScreenQuestionState($0, at: entry.date) }
    }

    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 2) {
                Label { Text(.widgetLockScreenQuestionName) } icon: { Image(systemName: "bubble.left.fill") }
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                Text(state.text(partnerName: entry.snapshot?.partnerFirstName ?? ""))
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LockScreenUnavailableView(symbol: "bubble.left", title: .widgetLockScreenQuestionName)
        }
    }
}
#endif
